from __future__ import annotations

import asyncio
import hashlib
import hmac
import json
import uuid
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from typing import Any, Protocol
from urllib.parse import quote, urlparse

import httpx
from sqlalchemy import select

from .api_errors import APIError
from .config import ProductionSettings
from .contracts_v2 import HostedURLResponse, WebhookAcceptedResponse
from .database import Database
from .models import AuditEvent, AuthSession, BetaInvite, Plan, Subscription, User, WebhookEvent
from .security import AccessClaims


PADDLE_SIGNATURE_TOLERANCE_SECONDS = 300
MAX_PADDLE_WEBHOOK_BYTES = 256 * 1024


class PaddleUnavailableError(RuntimeError):
    pass


class PaddleRejectedError(RuntimeError):
    pass


@dataclass(frozen=True)
class PaddleWebhookProjection:
    event_id: str
    event_type: str
    occurred_at: datetime
    subscription_id: str
    customer_id: str
    status: str
    product_id: str
    price_id: str
    period_start: datetime
    period_end: datetime
    scheduled_change: str | None
    scheduled_change_effective_at: datetime | None
    snapcal_user_id: uuid.UUID | None


class PaddleWebhookDispatching(Protocol):
    async def dispatch(self, projection: PaddleWebhookProjection) -> None: ...


class PaddleClient:
    def __init__(
        self,
        *,
        api_key: str,
        environment: str,
        price_id: str,
        client: httpx.AsyncClient | None = None,
    ) -> None:
        self._api_key = api_key
        self._price_id = price_id
        base_url = (
            "https://sandbox-api.paddle.com"
            if environment == "sandbox"
            else "https://api.paddle.com"
        )
        self._base_url = base_url
        self._client = client or httpx.AsyncClient(
            timeout=httpx.Timeout(15),
            limits=httpx.Limits(max_connections=10, max_keepalive_connections=5),
        )
        self._owns_client = client is None

    async def close(self) -> None:
        if self._owns_client:
            await self._client.aclose()

    async def checkout_url(
        self,
        *,
        user_id: uuid.UUID,
        checkout_page_url: str,
    ) -> str:
        envelope = await self._request(
            "POST",
            "/transactions",
            {
                "items": [{"price_id": self._price_id, "quantity": 1}],
                "custom_data": {"snapcal_user_id": str(user_id)},
                "checkout": {"url": checkout_page_url},
            },
        )
        return _hosted_url(envelope, ("data", "checkout", "url"))

    async def portal_url(self, customer_id: str) -> str:
        envelope = await self._request(
            "POST",
            f"/customers/{quote(customer_id, safe='')}/portal-sessions",
            {},
        )
        return _hosted_url(envelope, ("data", "urls", "general", "overview"))

    async def _request(
        self, method: str, path: str, payload: dict[str, Any]
    ) -> dict[str, Any]:
        try:
            response = await self._client.request(
                method,
                f"{self._base_url}{path}",
                headers={
                    "Authorization": f"Bearer {self._api_key}",
                    "Content-Type": "application/json",
                },
                json=payload,
            )
        except (httpx.TimeoutException, httpx.NetworkError, httpx.HTTPError) as error:
            raise PaddleUnavailableError("Paddle is unavailable") from error
        if response.status_code == 429 or response.status_code >= 500:
            raise PaddleUnavailableError("Paddle is unavailable")
        if response.status_code < 200 or response.status_code >= 300:
            raise PaddleRejectedError("Paddle rejected the request")
        try:
            envelope = response.json()
            if not isinstance(envelope, dict):
                raise TypeError("Paddle response must be an object")
            return envelope
        except (ValueError, TypeError) as error:
            raise PaddleRejectedError("Paddle response is invalid") from error


class InlinePaddleDispatcher:
    def __init__(self) -> None:
        self._handler: Any = None

    def set_handler(self, handler: Any) -> None:
        self._handler = handler

    async def dispatch(self, projection: PaddleWebhookProjection) -> None:
        if self._handler is None:
            raise PaddleUnavailableError("Paddle webhook dispatcher is unavailable")
        await self._handler(projection)


class BillingService:
    def __init__(
        self,
        *,
        settings: ProductionSettings,
        database: Database,
        paddle: PaddleClient,
        dispatcher: PaddleWebhookDispatching | None = None,
    ) -> None:
        self.settings = settings
        self.database = database
        self.paddle = paddle
        selected = dispatcher or InlinePaddleDispatcher()
        if isinstance(selected, InlinePaddleDispatcher):
            selected.set_handler(self.apply_webhook)
        self.dispatcher = selected

    async def close(self) -> None:
        await self.paddle.close()

    async def checkout(self, claims: AccessClaims) -> HostedURLResponse:
        user = await self._billing_user(claims, require_subscription=False)
        checkout_page_url = f"{self.settings.web_base_url}/checkout"
        try:
            url = await self.paddle.checkout_url(
                user_id=user.id,
                checkout_page_url=checkout_page_url,
            )
        except PaddleUnavailableError:
            raise APIError(
                code="billing_unavailable",
                message="Checkout is temporarily unavailable.",
                status_code=503,
                retryable=True,
            ) from None
        except PaddleRejectedError:
            raise APIError(
                code="billing_request_rejected",
                message="Checkout could not be created.",
                status_code=502,
            ) from None
        await self._record_audit(user.id, "checkout_created")
        return HostedURLResponse(url=url)

    async def portal(self, claims: AccessClaims) -> HostedURLResponse:
        user = await self._billing_user(claims, require_subscription=True)
        async with self.database.session() as session:
            subscription = await session.scalar(
                select(Subscription).where(Subscription.user_id == user.id)
            )
        if subscription is None:
            raise APIError(
                code="subscription_not_found",
                message="No SnapCal subscription is available to manage.",
                status_code=404,
            )
        try:
            url = await self.paddle.portal_url(subscription.paddle_customer_id)
        except PaddleUnavailableError:
            raise APIError(
                code="billing_unavailable",
                message="Manage Billing is temporarily unavailable.",
                status_code=503,
                retryable=True,
            ) from None
        except PaddleRejectedError:
            raise APIError(
                code="billing_request_rejected",
                message="Manage Billing could not be opened.",
                status_code=502,
            ) from None
        await self._record_audit(user.id, "portal_created")
        return HostedURLResponse(url=url)

    async def ingest_webhook(
        self,
        *,
        raw_body: bytes,
        signature: str | None,
        now: datetime | None = None,
    ) -> WebhookAcceptedResponse:
        received_at = now or datetime.now(UTC)
        if not raw_body or len(raw_body) > MAX_PADDLE_WEBHOOK_BYTES:
            raise APIError(
                code="invalid_webhook",
                message="The webhook body is invalid.",
                status_code=400,
            )
        verify_paddle_signature(
            raw_body=raw_body,
            signature=signature,
            secret=self.settings.paddle_webhook_secret,
            now=received_at,
        )
        projection = parse_paddle_webhook(raw_body)
        duplicate = False
        should_dispatch = True
        async with self.database.session() as session:
            async with session.begin():
                existing = await session.get(WebhookEvent, projection.event_id)
                if existing is None:
                    session.add(
                        WebhookEvent(
                            event_id=projection.event_id,
                            event_type=projection.event_type,
                            occurred_at=projection.occurred_at,
                            processing_state="received",
                        )
                    )
                else:
                    duplicate = True
                    should_dispatch = existing.processing_state in {"received", "failed"}
        if should_dispatch:
            try:
                async with asyncio.timeout(3.0):
                    await self.dispatcher.dispatch(projection)
            except Exception:
                await self._mark_webhook_failed(projection.event_id, "dispatch_failed")
                raise APIError(
                    code="webhook_dispatch_unavailable",
                    message="Webhook processing is temporarily unavailable.",
                    status_code=503,
                    retryable=True,
                ) from None
        return WebhookAcceptedResponse(duplicate=duplicate)

    async def apply_webhook(self, projection: PaddleWebhookProjection) -> None:
        try:
            await self._apply_webhook(projection)
        except PaddleRejectedError:
            # The database transaction that rejected the projection is rolled
            # back. Persist redacted failure metadata separately so a retry or
            # operator can see the event without retaining its raw payload.
            await self._mark_webhook_failed(
                projection.event_id, "projection_rejected"
            )
            raise

    async def _apply_webhook(self, projection: PaddleWebhookProjection) -> None:
        now = datetime.now(UTC)
        async with self.database.session() as session:
            async with session.begin():
                event = await session.scalar(
                    select(WebhookEvent)
                    .where(WebhookEvent.event_id == projection.event_id)
                    .with_for_update()
                )
                if event is None or event.processing_state in {"processed", "ignored"}:
                    return
                subscription = await session.scalar(
                    select(Subscription)
                    .where(
                        (Subscription.paddle_subscription_id == projection.subscription_id)
                        | (Subscription.paddle_customer_id == projection.customer_id)
                    )
                    .with_for_update()
                )
                user = None
                if projection.snapcal_user_id is not None:
                    user = await session.get(User, projection.snapcal_user_id)
                if user is None and subscription is not None:
                    user = await session.get(User, subscription.user_id)
                if user is None:
                    event.processing_state = "failed"
                    event.failure_code = "user_not_found"
                    event.failure_count += 1
                    raise PaddleRejectedError("webhook user was not found")
                if (
                    subscription is not None
                    and _utc(subscription.last_event_occurred_at) > projection.occurred_at
                ):
                    event.processing_state = "ignored"
                    event.processed_at = now
                    return
                plan = await session.scalar(
                    select(Plan).where(Plan.paddle_price_id == projection.price_id)
                )
                if plan is None and projection.price_id == self.settings.paddle_price_id:
                    plan = await session.get(Plan, "pro_beta")
                if plan is None:
                    event.processing_state = "failed"
                    event.failure_code = "plan_not_found"
                    event.failure_count += 1
                    raise PaddleRejectedError("webhook plan was not found")
                if subscription is None:
                    subscription = Subscription(
                        user_id=user.id,
                        plan_code=plan.code,
                        paddle_customer_id=projection.customer_id,
                        paddle_subscription_id=projection.subscription_id,
                        status=projection.status,
                        product_id=projection.product_id,
                        price_id=projection.price_id,
                        current_period_start=projection.period_start,
                        current_period_end=projection.period_end,
                        scheduled_change=projection.scheduled_change,
                        scheduled_change_effective_at=projection.scheduled_change_effective_at,
                        last_event_occurred_at=projection.occurred_at,
                    )
                    session.add(subscription)
                else:
                    subscription.plan_code = plan.code
                    subscription.paddle_customer_id = projection.customer_id
                    subscription.paddle_subscription_id = projection.subscription_id
                    subscription.status = projection.status
                    subscription.product_id = projection.product_id
                    subscription.price_id = projection.price_id
                    subscription.current_period_start = projection.period_start
                    subscription.current_period_end = projection.period_end
                    subscription.scheduled_change = projection.scheduled_change
                    subscription.scheduled_change_effective_at = (
                        projection.scheduled_change_effective_at
                    )
                    subscription.last_event_occurred_at = projection.occurred_at
                    subscription.updated_at = now
                event.processing_state = "processed"
                event.failure_code = None
                event.processed_at = now
                session.add(
                    _billing_audit(
                        user.id,
                        "entitlement_changed",
                        projection.status,
                        now,
                    )
                )

    async def _billing_user(
        self, claims: AccessClaims, *, require_subscription: bool
    ) -> User:
        now = datetime.now(UTC)
        async with self.database.session() as session:
            async with session.begin():
                auth_session = await session.get(AuthSession, claims.session_id)
                if (
                    auth_session is None
                    or auth_session.user_id != claims.user_id
                    or auth_session.device_identifier != claims.device_id
                    or auth_session.revoked_at is not None
                    or _utc(auth_session.expires_at) <= now
                ):
                    raise APIError(
                        code="session_expired",
                        message="Sign in again to continue.",
                        status_code=401,
                    )
                user = await session.get(User, claims.user_id)
                if user is None or user.deleted_at is not None:
                    raise APIError(
                        code="session_expired",
                        message="Sign in again to continue.",
                        status_code=401,
                    )
                invite = await session.scalar(
                    select(BetaInvite).where(BetaInvite.email_normalized == user.email_normalized)
                )
                if (
                    invite is None
                    or invite.state not in {"invited", "activated"}
                    or _utc(invite.expires_at) <= now
                ):
                    raise APIError(
                        code="invitation_required",
                        message="Billing is limited to invited beta users.",
                        status_code=403,
                    )
                if require_subscription:
                    subscription = await session.scalar(
                        select(Subscription).where(Subscription.user_id == user.id)
                    )
                    if subscription is None:
                        raise APIError(
                            code="subscription_not_found",
                            message="No SnapCal subscription is available to manage.",
                            status_code=404,
                        )
        return user

    async def _record_audit(self, user_id: uuid.UUID, action: str) -> None:
        now = datetime.now(UTC)
        async with self.database.session() as session:
            async with session.begin():
                session.add(_billing_audit(user_id, action, None, now))

    async def _mark_webhook_failed(self, event_id: str, code: str) -> None:
        async with self.database.session() as session:
            async with session.begin():
                event = await session.get(WebhookEvent, event_id)
                if event is not None:
                    event.processing_state = "failed"
                    event.failure_code = code
                    event.failure_count += 1


def verify_paddle_signature(
    *, raw_body: bytes, signature: str | None, secret: str, now: datetime
) -> None:
    if not signature:
        raise APIError(
            code="invalid_webhook_signature",
            message="The webhook signature is invalid.",
            status_code=401,
        )
    timestamp: int | None = None
    signatures: list[str] = []
    for part in signature.split(";"):
        key, separator, value = part.strip().partition("=")
        if not separator:
            continue
        if key == "ts":
            try:
                timestamp = int(value)
            except ValueError:
                timestamp = None
        elif key == "h1" and value:
            signatures.append(value)
    current = int(now.timestamp())
    if timestamp is None or abs(current - timestamp) > PADDLE_SIGNATURE_TOLERANCE_SECONDS:
        raise APIError(
            code="invalid_webhook_signature",
            message="The webhook signature is invalid.",
            status_code=401,
        )
    signed = str(timestamp).encode("ascii") + b":" + raw_body
    expected = hmac.new(secret.encode("utf-8"), signed, hashlib.sha256).hexdigest()
    if not any(hmac.compare_digest(expected, candidate) for candidate in signatures):
        raise APIError(
            code="invalid_webhook_signature",
            message="The webhook signature is invalid.",
            status_code=401,
        )


def parse_paddle_webhook(raw_body: bytes) -> PaddleWebhookProjection:
    try:
        envelope = json.loads(raw_body)
        event_id = _string(envelope, "event_id")
        event_type = _string(envelope, "event_type")
        if not event_type.startswith("subscription."):
            raise ValueError("unsupported event type")
        occurred_at = _timestamp(envelope.get("occurred_at"))
        data = envelope["data"]
        if not isinstance(data, dict):
            raise TypeError("data")
        subscription_id = _string(data, "id")
        customer_id = _string(data, "customer_id")
        status = _string(data, "status")
        if status not in {"trialing", "active", "past_due", "paused", "canceled"}:
            raise ValueError("unsupported subscription status")
        period = data.get("current_billing_period")
        if period is None and status in {"paused", "canceled"}:
            period = {
                "starts_at": occurred_at.isoformat(),
                "ends_at": occurred_at.isoformat(),
            }
        if not isinstance(period, dict):
            raise TypeError("period")
        items = data["items"]
        if not isinstance(items, list) or not items or not isinstance(items[0], dict):
            raise TypeError("items")
        price = items[0]["price"]
        if not isinstance(price, dict):
            raise TypeError("price")
        scheduled = data.get("scheduled_change")
        action = None
        effective_at = None
        if scheduled is not None:
            if not isinstance(scheduled, dict):
                raise TypeError("scheduled_change")
            action = _string(scheduled, "action")
            effective_at = _timestamp(scheduled.get("effective_at"))
        custom_data = data.get("custom_data") or {}
        if not isinstance(custom_data, dict):
            custom_data = {}
        user_id = custom_data.get("snapcal_user_id")
        return PaddleWebhookProjection(
            event_id=event_id,
            event_type=event_type,
            occurred_at=occurred_at,
            subscription_id=subscription_id,
            customer_id=customer_id,
            status=status,
            product_id=_string(price, "product_id"),
            price_id=_string(price, "id"),
            period_start=_timestamp(period.get("starts_at")),
            period_end=_timestamp(period.get("ends_at")),
            scheduled_change=action,
            scheduled_change_effective_at=effective_at,
            snapcal_user_id=uuid.UUID(user_id) if isinstance(user_id, str) else None,
        )
    except (KeyError, TypeError, ValueError, json.JSONDecodeError) as error:
        raise APIError(
            code="invalid_webhook",
            message="The webhook body is invalid.",
            status_code=400,
        ) from error


def _hosted_url(envelope: dict[str, Any], path: tuple[str, ...]) -> str:
    value: Any = envelope
    try:
        for key in path:
            value = value[key]
    except (KeyError, TypeError) as error:
        raise PaddleRejectedError("Paddle response omitted a hosted URL") from error
    parsed = urlparse(value) if isinstance(value, str) else None
    if parsed is None or parsed.scheme != "https" or not parsed.netloc:
        raise PaddleRejectedError("Paddle returned an invalid hosted URL")
    return value


def _string(mapping: dict[str, Any], key: str) -> str:
    value = mapping[key]
    if not isinstance(value, str) or not value.strip():
        raise TypeError(key)
    return value.strip()


def _timestamp(value: Any) -> datetime:
    if not isinstance(value, str):
        raise TypeError("timestamp")
    parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    if parsed.tzinfo is None:
        raise ValueError("timestamp must include timezone")
    return parsed.astimezone(UTC)


def _billing_audit(
    user_id: uuid.UUID, action: str, reason: str | None, now: datetime
) -> AuditEvent:
    return AuditEvent(
        user_id=user_id,
        action=action,
        reason_code=reason,
        expires_at=now + timedelta(days=90),
    )


def _utc(value: datetime) -> datetime:
    return value.replace(tzinfo=UTC) if value.tzinfo is None else value.astimezone(UTC)
