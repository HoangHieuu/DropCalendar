from __future__ import annotations

import base64
import asyncio
import json
import logging
import uuid
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from decimal import Decimal
from time import monotonic
from typing import Protocol

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.x25519 import (
    X25519PrivateKey,
    X25519PublicKey,
)
from cryptography.hazmat.primitives.ciphers.aead import ChaCha20Poly1305
from cryptography.hazmat.primitives.kdf.hkdf import HKDF
from cryptography.hazmat.primitives import hashes
from sqlalchemy import delete, func, select

from .api_errors import APIError
from .config import ProductionSettings
from .contracts import ExtractionRequest
from .contracts_v2 import (
    GoogleExchangeRequest,
    GoogleExchangeResponse,
    GoogleTransientTokens,
    MeResponse,
    PlanResponse,
    QuotaSnapshot,
    RetryEnvelopeResponse,
    SessionTokens,
    V2ExtractionMetadata,
    V2ExtractionResponse,
)
from .database import Database
from .identity import (
    GoogleIdentityExchanging,
    IdentityRejectedError,
    IdentityUnavailableError,
)
from .models import (
    AuditEvent,
    AuthSession,
    BetaInvite,
    ExtractionRequestRecord,
    OperationalDailyStat,
    Plan,
    Subscription,
    UsagePeriod,
    User,
    WebhookEvent,
)
from .provider import (
    BenchmarkExtractionProvider,
    InvalidProviderOutputError,
    ProviderAccounting,
    ProviderRejectedError,
    ProviderUnavailableError,
    ProviderUsageUnavailableError,
)
from .security import (
    AccessClaims,
    InvalidAccessTokenError,
    SessionTokenCodec,
    constant_time_equal,
    input_hmac,
    secret_hash,
)


ENTITLED_SUBSCRIPTION_STATES = {"trialing", "active", "past_due"}
AUDIT_RETENTION_DAYS = 90
logger = logging.getLogger(__name__)


class ResultCleanupScheduling(Protocol):
    async def schedule_result_cleanup(
        self, request_id: uuid.UUID, expires_at: datetime
    ) -> None: ...


@dataclass(frozen=True)
class Reservation:
    request_id: uuid.UUID
    usage_period_id: uuid.UUID
    quota: QuotaSnapshot


class ProductionService:
    def __init__(
        self,
        *,
        settings: ProductionSettings,
        database: Database,
        identity: GoogleIdentityExchanging,
        provider: BenchmarkExtractionProvider,
        result_cleanup_scheduler: ResultCleanupScheduling | None = None,
    ) -> None:
        self.settings = settings
        self.database = database
        self.identity = identity
        self.provider = provider
        self.result_cleanup_scheduler = result_cleanup_scheduler
        self.tokens = SessionTokenCodec(
            settings.session_signing_key,
            settings.access_token_ttl_seconds,
        )

    async def close(self) -> None:
        close_identity = getattr(self.identity, "close", None)
        if close_identity is not None:
            await close_identity()
        await self.database.dispose()

    def decode_access_token(self, token: str) -> AccessClaims:
        try:
            return self.tokens.decode(token)
        except InvalidAccessTokenError:
            raise APIError(
                code="authentication_required",
                message="Sign in to use Accuracy Mode.",
                status_code=401,
            ) from None

    async def exchange_google(
        self, request: GoogleExchangeRequest
    ) -> GoogleExchangeResponse:
        try:
            identity = await self.identity.exchange(request)
        except IdentityUnavailableError:
            raise APIError(
                code="identity_provider_unavailable",
                message="Google sign-in is temporarily unavailable.",
                status_code=503,
                retryable=True,
            ) from None
        except IdentityRejectedError:
            raise APIError(
                code="identity_exchange_rejected",
                message="Google could not complete sign-in.",
                status_code=400,
            ) from None

        now = datetime.now(UTC)
        refresh_expires_at = now + timedelta(days=self.settings.refresh_token_ttl_days)
        async with self.database.session() as session:
            async with session.begin():
                user = await session.scalar(
                    select(User).where(User.google_subject == identity.subject).with_for_update()
                )
                email_user = await session.scalar(
                    select(User).where(User.email_normalized == identity.email).with_for_update()
                )
                if user is not None and email_user is not None and user.id != email_user.id:
                    raise APIError(
                        code="identity_conflict",
                        message="This Google account cannot be linked automatically.",
                        status_code=409,
                    )
                if user is None:
                    if email_user is not None and email_user.google_subject != identity.subject:
                        raise APIError(
                            code="identity_conflict",
                            message="This Google account cannot be linked automatically.",
                            status_code=409,
                        )
                    user = email_user or User(
                        email_normalized=identity.email,
                        google_subject=identity.subject,
                    )
                    session.add(user)
                    await session.flush()
                if user.deleted_at is not None:
                    raise APIError(
                        code="account_deleted",
                        message="This SnapCal account is unavailable.",
                        status_code=403,
                    )

                invite = await session.scalar(
                    select(BetaInvite)
                    .where(BetaInvite.email_normalized == identity.email)
                    .with_for_update()
                )
                invited = _invite_active(invite, now)
                if invited and invite is not None and invite.state != "activated":
                    invite.state = "activated"
                    invite.activation_user_id = user.id
                    invite.activated_at = now

                auth_session = await session.scalar(
                    select(AuthSession)
                    .where(
                        AuthSession.user_id == user.id,
                        AuthSession.device_identifier == request.device_id,
                    )
                    .with_for_update()
                )
                if auth_session is None:
                    auth_session = AuthSession(
                        user_id=user.id,
                        device_identifier=request.device_id,
                        refresh_token_hash="pending",
                        expires_at=refresh_expires_at,
                        last_used_at=now,
                    )
                    session.add(auth_session)
                    await session.flush()
                refresh_token = self.tokens.refresh_token(auth_session.id)
                auth_session.previous_refresh_token_hash = None
                auth_session.refresh_token_hash = secret_hash(
                    refresh_token, self.settings.session_signing_key
                )
                auth_session.expires_at = refresh_expires_at
                auth_session.revoked_at = None
                auth_session.last_used_at = now
                session.add(_audit(user.id, "login", None, now))

        access_token, access_expires_at = self.tokens.access_token(
            user_id=user.id,
            session_id=auth_session.id,
            device_id=request.device_id,
        )
        return GoogleExchangeResponse(
            user_id=str(user.id),
            email=identity.email,
            invited=invited,
            session=SessionTokens(
                access_token=access_token,
                access_token_expires_at=access_expires_at,
                refresh_token=refresh_token,
                refresh_token_expires_at=refresh_expires_at,
            ),
            google=GoogleTransientTokens(
                access_token=identity.access_token,
                expires_in=identity.expires_in,
                refresh_token=identity.refresh_token,
            ),
        )

    async def refresh_session(self, refresh_token: str) -> SessionTokens:
        try:
            session_id = self.tokens.refresh_session_id(refresh_token)
        except InvalidAccessTokenError:
            raise APIError(
                code="invalid_refresh_token",
                message="Sign in again to continue.",
                status_code=401,
            ) from None
        provided_hash = secret_hash(refresh_token, self.settings.session_signing_key)
        now = datetime.now(UTC)
        rotated: tuple[AuthSession, str, datetime] | None = None
        reuse_detected = False
        async with self.database.session() as session:
            async with session.begin():
                record = await session.scalar(
                    select(AuthSession).where(AuthSession.id == session_id).with_for_update()
                )
                if record is None or record.revoked_at is not None or _utc(record.expires_at) <= now:
                    pass
                elif constant_time_equal(record.previous_refresh_token_hash, provided_hash):
                    record.revoked_at = now
                    reuse_detected = True
                    session.add(_audit(record.user_id, "session_revoked", "token_reuse", now))
                elif constant_time_equal(record.refresh_token_hash, provided_hash):
                    next_token = self.tokens.refresh_token(record.id)
                    record.previous_refresh_token_hash = record.refresh_token_hash
                    record.refresh_token_hash = secret_hash(
                        next_token, self.settings.session_signing_key
                    )
                    record.last_used_at = now
                    record.expires_at = now + timedelta(days=self.settings.refresh_token_ttl_days)
                    rotated = (record, next_token, record.expires_at)
        if reuse_detected:
            raise APIError(
                code="refresh_token_reused",
                message="This device session was revoked. Sign in again.",
                status_code=401,
            )
        if rotated is None:
            raise APIError(
                code="invalid_refresh_token",
                message="Sign in again to continue.",
                status_code=401,
            )
        record, next_token, refresh_expires_at = rotated
        access_token, access_expires_at = self.tokens.access_token(
            user_id=record.user_id,
            session_id=record.id,
            device_id=record.device_identifier,
        )
        return SessionTokens(
            access_token=access_token,
            access_token_expires_at=access_expires_at,
            refresh_token=next_token,
            refresh_token_expires_at=refresh_expires_at,
        )

    async def logout(self, claims: AccessClaims) -> None:
        now = datetime.now(UTC)
        async with self.database.session() as session:
            async with session.begin():
                record = await session.scalar(
                    select(AuthSession)
                    .where(
                        AuthSession.id == claims.session_id,
                        AuthSession.user_id == claims.user_id,
                        AuthSession.device_identifier == claims.device_id,
                    )
                    .with_for_update()
                )
                if record is not None and record.revoked_at is None:
                    record.revoked_at = now
                    session.add(_audit(claims.user_id, "logout", None, now))

    async def plans(self) -> list[PlanResponse]:
        async with self.database.session() as session:
            records = (
                await session.scalars(select(Plan).where(Plan.active.is_(True)).order_by(Plan.price_usd_cents))
            ).all()
        return [_plan_response(plan) for plan in records]

    async def me(self, claims: AccessClaims) -> MeResponse:
        now = datetime.now(UTC)
        async with self.database.session() as session:
            async with session.begin():
                await _require_active_session(session, claims, now)
                user = await session.get(User, claims.user_id)
                if user is None or user.deleted_at is not None:
                    raise _authentication_error()
                invite = await session.scalar(
                    select(BetaInvite).where(BetaInvite.email_normalized == user.email_normalized)
                )
                subscription = await session.scalar(
                    select(Subscription).where(Subscription.user_id == user.id)
                )
                plan, entitled = await _selected_plan(session, subscription, now)
                usage = None
                if entitled and subscription is not None:
                    usage = await session.scalar(
                        select(UsagePeriod).where(
                            UsagePeriod.user_id == user.id,
                            UsagePeriod.period_start == subscription.current_period_start,
                            UsagePeriod.period_end == subscription.current_period_end,
                        )
                    )
        return MeResponse(
            user_id=str(user.id),
            email=user.email_normalized,
            invited=_invite_active(invite, now),
            subscription_status=subscription.status if subscription is not None else "none",
            plan=_plan_response(plan),
            quota=_quota_snapshot(plan, usage, subscription.current_period_end if subscription else None),
            payment_warning=subscription is not None and subscription.status == "past_due",
        )

    async def reserve(
        self,
        *,
        claims: AccessClaims,
        idempotency_key: str,
        image: bytes,
    ) -> Reservation:
        now = datetime.now(UTC)
        digest = input_hmac(user_id=claims.user_id, image=image, key=self.settings.input_hmac_key)
        async with self.database.session() as session:
            async with session.begin():
                await _require_active_session(session, claims, now)
                user = await session.scalar(
                    select(User).where(User.id == claims.user_id).with_for_update()
                )
                if user is None or user.deleted_at is not None:
                    raise _authentication_error()
                existing = await session.scalar(
                    select(ExtractionRequestRecord).where(
                        ExtractionRequestRecord.user_id == claims.user_id,
                        ExtractionRequestRecord.idempotency_key == idempotency_key,
                    )
                )
                if existing is not None:
                    if existing.input_hmac != digest:
                        raise APIError(
                            code="idempotency_conflict",
                            message="This idempotency key was used for another image.",
                            status_code=409,
                            request_id=existing.id,
                        )
                    code = "request_in_progress" if existing.state == "reserved" else "request_complete"
                    raise APIError(
                        code=code,
                        message=(
                            "This Accuracy request is still processing."
                            if code == "request_in_progress"
                            else "This Accuracy request has already completed."
                        ),
                        status_code=409,
                        retryable=code == "request_in_progress",
                        request_id=existing.id,
                    )

                invite = await session.scalar(
                    select(BetaInvite).where(BetaInvite.email_normalized == user.email_normalized)
                )
                if not _invite_active(invite, now):
                    raise APIError(
                        code="invitation_required",
                        message="Accuracy Mode is currently limited to invited beta users.",
                        status_code=403,
                    )
                subscription = await session.scalar(
                    select(Subscription)
                    .where(Subscription.user_id == user.id)
                    .with_for_update()
                )
                plan, entitled = await _selected_plan(session, subscription, now)
                if not entitled or subscription is None or not plan.accuracy_enabled:
                    raise APIError(
                        code="subscription_required",
                        message="An active SnapCal Pro subscription is required.",
                        status_code=403,
                    )

                usage = await session.scalar(
                    select(UsagePeriod)
                    .where(
                        UsagePeriod.user_id == user.id,
                        UsagePeriod.period_start == subscription.current_period_start,
                        UsagePeriod.period_end == subscription.current_period_end,
                    )
                    .with_for_update()
                )
                if usage is None:
                    usage = UsagePeriod(
                        user_id=user.id,
                        period_start=subscription.current_period_start,
                        period_end=subscription.current_period_end,
                        quota_limit=plan.monthly_quota,
                    )
                    session.add(usage)
                    await session.flush()
                if usage.reserved_units + usage.consumed_units >= usage.quota_limit:
                    raise APIError(
                        code="quota_exhausted",
                        message="Accuracy quota is exhausted for this billing period.",
                        status_code=402,
                    )

                concurrent = await session.scalar(
                    select(func.count()).select_from(ExtractionRequestRecord).where(
                        ExtractionRequestRecord.user_id == user.id,
                        ExtractionRequestRecord.state == "reserved",
                    )
                )
                if int(concurrent or 0) >= plan.concurrent_limit:
                    raise APIError(
                        code="concurrent_limit_exceeded",
                        message="Two Accuracy requests are already processing.",
                        status_code=429,
                        retryable=True,
                    )
                await _enforce_rate_limit(session, user.id, plan, now)
                await _enforce_provider_budget(
                    session, now, self.settings.provider_monthly_budget_usd
                )

                record = ExtractionRequestRecord(
                    user_id=user.id,
                    usage_period_id=usage.id,
                    idempotency_key=idempotency_key,
                    input_hmac=digest,
                    state="reserved",
                    quota_reserved=True,
                    model=self.provider.model,
                )
                session.add(record)
                usage.reserved_units += 1
                usage.updated_at = now
                await session.flush()
                quota = _quota_snapshot(plan, usage, subscription.current_period_end)
        return Reservation(request_id=record.id, usage_period_id=usage.id, quota=quota)

    async def record_reservation_denial(
        self, claims: AccessClaims, reason_code: str
    ) -> None:
        allowed = {
            "invitation_required",
            "subscription_required",
            "quota_exhausted",
            "concurrent_limit_exceeded",
            "rate_limit_exceeded",
            "daily_limit_exceeded",
            "provider_budget_exhausted",
        }
        if reason_code not in allowed:
            return
        now = datetime.now(UTC)
        async with self.database.session() as session:
            async with session.begin():
                session.add(
                    _audit(
                        claims.user_id,
                        "quota_denied",
                        reason_code,
                        now,
                    )
                )

    async def run_extraction(
        self,
        *,
        claims: AccessClaims,
        reservation: Reservation,
        image: bytes,
        metadata: V2ExtractionMetadata,
        started_at: float,
    ) -> V2ExtractionResponse:
        request = ExtractionRequest(
            schema_version="1",
            image_base64=base64.b64encode(image).decode("ascii"),
            mime_type="image/jpeg",
            captured_at=metadata.captured_at,
            time_zone=metadata.time_zone,
            locale=metadata.locale,
            ocr_lines=metadata.ocr_lines,
        )
        provider_started = monotonic()
        finalization_started = False
        try:
            async with asyncio.timeout(25):
                result = await self.provider.extract_with_usage(request)
            if not result.events or len(result.events) > 10:
                raise InvalidProviderOutputError(
                    "Provider returned an invalid event count",
                    accounting=ProviderAccounting(
                        request_cost_usd=result.request_cost_usd,
                        generation_id=result.generation_id,
                        input_tokens=result.input_tokens,
                        output_tokens=result.output_tokens,
                    ),
                )
            provider_latency_ms = round((monotonic() - provider_started) * 1000)
            envelope = _seal_result(
                public_key=metadata.retry_public_key,
                request_id=reservation.request_id,
                model=self.provider.model,
                events=[event.model_dump(mode="json") for event in result.events],
            )
            finalization_started = True
            quota = await self._finalize(
                claims=claims,
                reservation=reservation,
                succeeded=True,
                cost=result.request_cost_usd,
                generation_id=result.generation_id,
                input_tokens=result.input_tokens,
                output_tokens=result.output_tokens,
                provider_latency_ms=provider_latency_ms,
                total_latency_ms=round((monotonic() - started_at) * 1000),
                envelope=envelope,
                error_code=None,
            )
            return V2ExtractionResponse(
                request_id=str(reservation.request_id),
                model=self.provider.model,
                events=result.events,
                quota=quota,
            )
        except ProviderUnavailableError:
            await self._finalize_failure(
                claims, reservation, started_at, "provider_unavailable", provider_started
            )
            raise APIError(
                code="provider_unavailable",
                message="Accuracy Mode is temporarily unavailable. Local Only was not charged.",
                status_code=503,
                retryable=True,
                request_id=reservation.request_id,
            ) from None
        except TimeoutError:
            await self._finalize_failure(
                claims, reservation, started_at, "extraction_timeout", provider_started
            )
            raise APIError(
                code="timeout",
                message="Accuracy timed out. Local Only was not charged.",
                status_code=504,
                retryable=True,
                request_id=reservation.request_id,
            ) from None
        except ProviderRejectedError:
            await self._finalize_failure(
                claims, reservation, started_at, "provider_rejected_input", provider_started
            )
            raise APIError(
                code="provider_rejected_input",
                message="The provider could not process this image. Local Only was not charged.",
                status_code=502,
                request_id=reservation.request_id,
            ) from None
        except (InvalidProviderOutputError, ProviderUsageUnavailableError) as error:
            await self._finalize_failure(
                claims,
                reservation,
                started_at,
                "invalid_provider_output",
                provider_started,
                accounting=error.accounting,
            )
            raise APIError(
                code="invalid_provider_output",
                message="Accuracy returned an invalid result. Local Only was not charged.",
                status_code=502,
                request_id=reservation.request_id,
            ) from None
        except asyncio.CancelledError:
            if not finalization_started:
                await asyncio.shield(
                    self._finalize_failure(
                        claims,
                        reservation,
                        started_at,
                        "request_cancelled",
                        provider_started,
                    )
                )
            raise
        except Exception:
            if finalization_started:
                raise
            await self._finalize_failure(
                claims,
                reservation,
                started_at,
                "internal_error",
                provider_started,
            )
            raise APIError(
                code="internal_error",
                message="Accuracy could not complete this request. Local Only was not charged.",
                status_code=500,
                retryable=True,
                request_id=reservation.request_id,
            ) from None
    async def _finalize_failure(
        self,
        claims: AccessClaims,
        reservation: Reservation,
        started_at: float,
        error_code: str,
        provider_started: float,
        accounting: ProviderAccounting | None = None,
    ) -> None:
        await self._finalize(
            claims=claims,
            reservation=reservation,
            succeeded=False,
            cost=(
                accounting.request_cost_usd
                if accounting is not None
                and accounting.request_cost_usd is not None
                else Decimal("0")
            ),
            generation_id=accounting.generation_id if accounting is not None else None,
            input_tokens=accounting.input_tokens if accounting is not None else None,
            output_tokens=accounting.output_tokens if accounting is not None else None,
            provider_latency_ms=round((monotonic() - provider_started) * 1000),
            total_latency_ms=round((monotonic() - started_at) * 1000),
            envelope=None,
            error_code=error_code,
        )

    async def _finalize(
        self,
        *,
        claims: AccessClaims,
        reservation: Reservation,
        succeeded: bool,
        cost: Decimal,
        generation_id: str | None,
        input_tokens: int | None,
        output_tokens: int | None,
        provider_latency_ms: int,
        total_latency_ms: int,
        envelope: bytes | None,
        error_code: str | None,
    ) -> QuotaSnapshot:
        now = datetime.now(UTC)
        monthly_provider_cost = Decimal("0")
        async with self.database.session() as session:
            async with session.begin():
                record = await session.scalar(
                    select(ExtractionRequestRecord)
                    .where(
                        ExtractionRequestRecord.id == reservation.request_id,
                        ExtractionRequestRecord.user_id == claims.user_id,
                    )
                    .with_for_update()
                )
                usage = await session.scalar(
                    select(UsagePeriod)
                    .where(UsagePeriod.id == reservation.usage_period_id)
                    .with_for_update()
                )
                if record is None or usage is None or record.state != "reserved":
                    raise APIError(
                        code="request_state_invalid",
                        message="The Accuracy request could not be finalized safely.",
                        status_code=409,
                        request_id=reservation.request_id,
                    )
                if record.quota_reserved:
                    usage.reserved_units = max(0, usage.reserved_units - 1)
                    record.quota_reserved = False
                if succeeded:
                    usage.consumed_units += 1
                usage.actual_provider_cost_usd = Decimal(usage.actual_provider_cost_usd) + cost
                usage.updated_at = now
                record.state = "succeeded" if succeeded else "failed"
                record.provider_generation_id = generation_id
                record.input_tokens = input_tokens
                record.output_tokens = output_tokens
                record.provider_cost_usd = cost
                record.provider_latency_ms = provider_latency_ms
                record.total_latency_ms = total_latency_ms
                record.error_code = error_code
                record.encrypted_result_envelope = envelope
                record.result_expires_at = (
                    now + timedelta(seconds=self.settings.result_ttl_seconds)
                    if succeeded
                    else None
                )
                record.finalized_at = now
                session.add(
                    _audit(
                        claims.user_id,
                        "extraction_succeeded" if succeeded else "extraction_failed",
                        error_code,
                        now,
                        reservation.request_id,
                    )
                )
                await session.flush()
                month_start = now.replace(
                    day=1, hour=0, minute=0, second=0, microsecond=0
                )
                monthly_provider_cost = Decimal(
                    await session.scalar(
                        select(func.coalesce(func.sum(ExtractionRequestRecord.provider_cost_usd), 0))
                        .where(ExtractionRequestRecord.created_at >= month_start)
                    )
                    or 0
                )
        quota = QuotaSnapshot(
            limit=usage.quota_limit,
            used=usage.consumed_units,
            reserved=usage.reserved_units,
            remaining=max(0, usage.quota_limit - usage.consumed_units - usage.reserved_units),
            period_end=usage.period_end,
        )
        if succeeded and record.result_expires_at is not None:
            await self._schedule_result_cleanup(
                reservation.request_id, record.result_expires_at
            )
        _log_provider_budget_threshold(
            monthly_provider_cost, self.settings.provider_monthly_budget_usd
        )
        return quota

    async def _schedule_result_cleanup(
        self, request_id: uuid.UUID, expires_at: datetime
    ) -> None:
        if self.result_cleanup_scheduler is None:
            return
        try:
            await self.result_cleanup_scheduler.schedule_result_cleanup(
                request_id, expires_at
            )
        except Exception:
            # The daily authenticated cleanup is the safety net. Do not turn a
            # completed extraction into a visible failure or a duplicate retry.
            logger.exception(
                "retry envelope cleanup task enqueue failed",
                extra={"request_id": str(request_id)},
            )

    async def retry_envelope(
        self, claims: AccessClaims, request_id: uuid.UUID
    ) -> RetryEnvelopeResponse:
        now = datetime.now(UTC)
        async with self.database.session() as session:
            async with session.begin():
                await _require_active_session(session, claims, now)
                record = await session.scalar(
                    select(ExtractionRequestRecord).where(
                        ExtractionRequestRecord.id == request_id,
                        ExtractionRequestRecord.user_id == claims.user_id,
                    )
                )
        if record is None:
            raise APIError(
                code="request_not_found",
                message="This Accuracy request was not found.",
                status_code=404,
                request_id=request_id,
            )
        if (
            record.encrypted_result_envelope is None
            or record.result_expires_at is None
            or _utc(record.result_expires_at) <= now
        ):
            raise APIError(
                code="result_expired",
                message="This encrypted retry result has expired.",
                status_code=410,
                request_id=request_id,
            )
        return RetryEnvelopeResponse(
            request_id=str(request_id),
            envelope_base64=base64.urlsafe_b64encode(
                record.encrypted_result_envelope
            ).decode("ascii"),
            expires_at=record.result_expires_at,
        )

    async def purge_expired_envelopes(self) -> int:
        now = datetime.now(UTC)
        async with self.database.session() as session:
            async with session.begin():
                records = (
                    await session.scalars(
                        select(ExtractionRequestRecord)
                        .where(
                            ExtractionRequestRecord.encrypted_result_envelope.is_not(None),
                            ExtractionRequestRecord.result_expires_at <= now,
                        )
                        .with_for_update(skip_locked=True)
                    )
                ).all()
                for record in records:
                    record.encrypted_result_envelope = None
                    record.result_expires_at = None
        return len(records)

    async def run_daily_maintenance(self) -> dict[str, int]:
        """Deletes private retry data, then aggregates and removes 90-day metadata."""

        expired_envelopes = await self.purge_expired_envelopes()
        now = datetime.now(UTC)
        cutoff = now - timedelta(days=AUDIT_RETENTION_DAYS)
        deleted_requests = 0
        deleted_audits = 0
        async with self.database.session() as session:
            async with session.begin():
                old_requests = (
                    await session.scalars(
                        select(ExtractionRequestRecord)
                        .where(
                            ExtractionRequestRecord.finalized_at.is_not(None),
                            ExtractionRequestRecord.finalized_at < cutoff,
                        )
                        .with_for_update(skip_locked=True)
                    )
                ).all()
                aggregates: dict[
                    tuple[object, str, str], dict[str, int | Decimal]
                ] = {}
                for record in old_requests:
                    finalized_at = _utc(record.finalized_at or record.created_at)
                    key = (
                        finalized_at.date(),
                        record.model or "unknown",
                        record.state,
                    )
                    values = aggregates.setdefault(
                        key,
                        {
                            "count": 0,
                            "cost": Decimal("0"),
                            "provider_total": 0,
                            "provider_max": 0,
                            "total_total": 0,
                            "total_max": 0,
                        },
                    )
                    provider_latency = record.provider_latency_ms or 0
                    total_latency = record.total_latency_ms or 0
                    values["count"] = int(values["count"]) + 1
                    values["cost"] = Decimal(values["cost"]) + Decimal(
                        record.provider_cost_usd
                    )
                    values["provider_total"] = int(values["provider_total"]) + provider_latency
                    values["provider_max"] = max(int(values["provider_max"]), provider_latency)
                    values["total_total"] = int(values["total_total"]) + total_latency
                    values["total_max"] = max(int(values["total_max"]), total_latency)

                for (day, model, state), values in aggregates.items():
                    stat = await session.scalar(
                        select(OperationalDailyStat)
                        .where(
                            OperationalDailyStat.day == day,
                            OperationalDailyStat.environment == self.settings.environment,
                            OperationalDailyStat.model == model,
                            OperationalDailyStat.state == state,
                        )
                        .with_for_update()
                    )
                    if stat is None:
                        stat = OperationalDailyStat(
                            day=day,
                            environment=self.settings.environment,
                            model=model,
                            state=state,
                        )
                        session.add(stat)
                    stat.request_count += int(values["count"])
                    stat.provider_cost_usd = Decimal(stat.provider_cost_usd) + Decimal(
                        values["cost"]
                    )
                    stat.provider_latency_ms_total += int(values["provider_total"])
                    stat.provider_latency_ms_max = max(
                        stat.provider_latency_ms_max, int(values["provider_max"])
                    )
                    stat.total_latency_ms_total += int(values["total_total"])
                    stat.total_latency_ms_max = max(
                        stat.total_latency_ms_max, int(values["total_max"])
                    )
                    stat.updated_at = now

                for record in old_requests:
                    await session.delete(record)
                deleted_requests = len(old_requests)
                audit_result = await session.execute(
                    delete(AuditEvent).where(AuditEvent.expires_at <= now)
                )
                deleted_audits = int(audit_result.rowcount or 0)
                await session.execute(
                    delete(WebhookEvent).where(
                        WebhookEvent.received_at < cutoff,
                        WebhookEvent.processing_state.in_({"processed", "ignored"}),
                    )
                )
                await session.execute(
                    delete(AuthSession).where(AuthSession.expires_at < cutoff)
                )
                await session.execute(
                    delete(UsagePeriod).where(UsagePeriod.period_end < cutoff)
                )
        return {
            "expired_envelopes": expired_envelopes,
            "deleted_requests": deleted_requests,
            "deleted_audits": deleted_audits,
        }

    async def expire_retry_envelope(self, request_id: uuid.UUID) -> bool:
        now = datetime.now(UTC)
        async with self.database.session() as session:
            async with session.begin():
                record = await session.scalar(
                    select(ExtractionRequestRecord)
                    .where(ExtractionRequestRecord.id == request_id)
                    .with_for_update()
                )
                if record is None or record.encrypted_result_envelope is None:
                    return False
                if record.result_expires_at is not None and _utc(record.result_expires_at) > now:
                    raise APIError(
                        code="task_not_due",
                        message="The result cleanup task is not due.",
                        status_code=409,
                        retryable=True,
                        request_id=request_id,
                    )
                record.encrypted_result_envelope = None
                record.result_expires_at = None
        return True


async def _require_active_session(session: object, claims: AccessClaims, now: datetime) -> None:
    record = await session.scalar(  # type: ignore[attr-defined]
        select(AuthSession).where(
            AuthSession.id == claims.session_id,
            AuthSession.user_id == claims.user_id,
            AuthSession.device_identifier == claims.device_id,
        )
    )
    if record is None or record.revoked_at is not None or _utc(record.expires_at) <= now:
        raise _authentication_error()


async def _selected_plan(
    session: object,
    subscription: Subscription | None,
    now: datetime,
) -> tuple[Plan, bool]:
    entitled = _subscription_entitled(subscription, now)
    code = subscription.plan_code if entitled and subscription is not None else "free"
    plan = await session.get(Plan, code)  # type: ignore[attr-defined]
    if plan is None or not plan.active:
        raise APIError(
            code="plan_unavailable",
            message="SnapCal plan configuration is unavailable.",
            status_code=503,
            retryable=True,
        )
    return plan, entitled


def _subscription_entitled(subscription: Subscription | None, now: datetime) -> bool:
    if subscription is None or subscription.status not in ENTITLED_SUBSCRIPTION_STATES:
        return False
    if _utc(subscription.current_period_end) <= now:
        return False
    if (
        subscription.scheduled_change == "cancel"
        and subscription.scheduled_change_effective_at is not None
        and _utc(subscription.scheduled_change_effective_at) <= now
    ):
        return False
    return True


def _invite_active(invite: BetaInvite | None, now: datetime) -> bool:
    return (
        invite is not None
        and invite.state in {"invited", "activated"}
        and _utc(invite.expires_at) > now
    )


def _plan_response(plan: Plan) -> PlanResponse:
    return PlanResponse(
        code=plan.code,
        display_name=plan.display_name,
        price_usd_cents=plan.price_usd_cents,
        monthly_quota=plan.monthly_quota,
        per_minute_limit=plan.per_minute_limit,
        per_day_limit=plan.per_day_limit,
        concurrent_limit=plan.concurrent_limit,
        accuracy_enabled=plan.accuracy_enabled,
    )


def _quota_snapshot(
    plan: Plan,
    usage: UsagePeriod | None,
    period_end: datetime | None,
) -> QuotaSnapshot:
    used = usage.consumed_units if usage is not None else 0
    reserved = usage.reserved_units if usage is not None else 0
    limit = usage.quota_limit if usage is not None else plan.monthly_quota
    return QuotaSnapshot(
        limit=limit,
        used=used,
        reserved=reserved,
        remaining=max(0, limit - used - reserved),
        period_end=period_end,
    )


async def _enforce_rate_limit(session: object, user_id: uuid.UUID, plan: Plan, now: datetime) -> None:
    minute_count = await session.scalar(  # type: ignore[attr-defined]
        select(func.count()).select_from(ExtractionRequestRecord).where(
            ExtractionRequestRecord.user_id == user_id,
            ExtractionRequestRecord.created_at >= now - timedelta(minutes=1),
        )
    )
    day_count = await session.scalar(  # type: ignore[attr-defined]
        select(func.count()).select_from(ExtractionRequestRecord).where(
            ExtractionRequestRecord.user_id == user_id,
            ExtractionRequestRecord.created_at >= now - timedelta(days=1),
        )
    )
    if int(minute_count or 0) >= plan.per_minute_limit:
        raise APIError(
            code="rate_limit_exceeded",
            message="Too many Accuracy requests. Try again in a minute.",
            status_code=429,
            retryable=True,
        )
    if int(day_count or 0) >= plan.per_day_limit:
        raise APIError(
            code="daily_limit_exceeded",
            message="The daily Accuracy safety limit has been reached.",
            status_code=429,
        )


async def _enforce_provider_budget(
    session: object, now: datetime, ceiling: Decimal
) -> None:
    month_start = datetime(now.year, now.month, 1, tzinfo=UTC)
    spent = await session.scalar(  # type: ignore[attr-defined]
        select(func.coalesce(func.sum(ExtractionRequestRecord.provider_cost_usd), 0)).where(
            ExtractionRequestRecord.created_at >= month_start
        )
    )
    if Decimal(spent or 0) >= ceiling:
        raise APIError(
            code="provider_budget_exhausted",
            message="Accuracy is paused by the monthly safety budget.",
            status_code=503,
        )


def _seal_result(
    *, public_key: str, request_id: uuid.UUID, model: str, events: list[dict[str, object]]
) -> bytes:
    raw_key = base64.urlsafe_b64decode(public_key + "=" * (-len(public_key) % 4))
    plaintext = json.dumps(
        {
            "schema_version": "2",
            "request_id": str(request_id),
            "model": model,
            "events": events,
        },
        ensure_ascii=False,
        separators=(",", ":"),
    ).encode("utf-8")
    recipient = X25519PublicKey.from_public_bytes(raw_key)
    ephemeral = X25519PrivateKey.generate()
    shared_secret = ephemeral.exchange(recipient)
    key = HKDF(
        algorithm=hashes.SHA256(),
        length=32,
        salt=None,
        info=b"snapcal-retry-v1",
    ).derive(shared_secret)
    nonce = __import__("os").urandom(12)
    ciphertext = ChaCha20Poly1305(key).encrypt(nonce, plaintext, None)
    ephemeral_public = ephemeral.public_key().public_bytes(
        encoding=serialization.Encoding.Raw,
        format=serialization.PublicFormat.Raw,
    )
    return b"\x01" + ephemeral_public + nonce + ciphertext


def _authentication_error() -> APIError:
    return APIError(
        code="session_expired",
        message="Sign in again to continue.",
        status_code=401,
    )


def _audit(
    user_id: uuid.UUID | None,
    action: str,
    reason: str | None,
    now: datetime,
    request_id: uuid.UUID | None = None,
) -> AuditEvent:
    return AuditEvent(
        user_id=user_id,
        action=action,
        request_id=request_id,
        reason_code=reason,
        expires_at=now + timedelta(days=AUDIT_RETENTION_DAYS),
    )


def _utc(value: datetime) -> datetime:
    return value.replace(tzinfo=UTC) if value.tzinfo is None else value.astimezone(UTC)


def _log_provider_budget_threshold(cost: Decimal, ceiling: Decimal) -> None:
    ratio = cost / ceiling if ceiling > 0 else Decimal("1")
    threshold = None
    if ratio >= Decimal("1"):
        threshold = 100
    elif ratio >= Decimal("0.85"):
        threshold = 85
    elif ratio >= Decimal("0.70"):
        threshold = 70
    if threshold is not None:
        logger.warning(
            "provider_budget_threshold threshold=%s recorded_cost_usd=%s ceiling_usd=%s",
            threshold,
            cost,
            ceiling,
        )
