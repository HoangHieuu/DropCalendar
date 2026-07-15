from __future__ import annotations

import asyncio
import base64
import hashlib
import hmac
import json
import os
import uuid
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from decimal import Decimal
from pathlib import Path

import httpx
import pytest
import pytest_asyncio
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric.x25519 import X25519PrivateKey
from cryptography.hazmat.primitives.ciphers.aead import ChaCha20Poly1305
from cryptography.hazmat.primitives.kdf.hkdf import HKDF
from sqlalchemy import select

from app.config import ProductionSettings
from app.billing import BillingService, PaddleClient
from app.contracts import (
    EventProposal,
    ExtractionRequest,
    OAuthTokenRequest,
    OAuthTokenResponse,
)
from app.database import Database
from app.identity import GoogleIdentityResult
from app.main import create_app
from app.models import (
    AuthSession,
    AuditEvent,
    Base,
    BetaInvite,
    ExtractionRequestRecord,
    Plan,
    Subscription,
    UsagePeriod,
    User,
    WebhookEvent,
)
from app.production_service import ProductionService
from app.provider import (
    InvalidProviderOutputError,
    ProviderAccounting,
    ProviderExtractionResult,
    ProviderKeyStatus,
    ProviderUnavailableError,
)


JPEG = b"\xff\xd8\xff\xe0snapcal-v2-test"


def proposal(title: str = "Agentic AI Build Week") -> EventProposal:
    return EventProposal.model_validate(
        {
            "title": {
                "value": title,
                "evidence_text": title,
                "confidence": 0.98,
                "is_inferred": False,
            },
            "start": {
                "date": "2026-07-08",
                "time": None,
                "evidence_text": "July 8, 2026",
                "confidence": 0.96,
                "is_inferred": False,
            },
            "end": {
                "date": "2026-07-08",
                "time": None,
                "evidence_text": "July 8, 2026",
                "confidence": 0.96,
                "is_inferred": False,
            },
            "location": {
                "value": "Ho Chi Minh City",
                "evidence_text": "Ho Chi Minh City",
                "confidence": 0.9,
                "is_inferred": False,
            },
            "description": {
                "value": None,
                "evidence_text": None,
                "confidence": 0.7,
                "is_inferred": False,
            },
            "is_all_day": True,
            "ambiguities": [],
        }
    )


@dataclass
class FakeIdentity:
    email: str = "beta@example.com"

    async def exchange(self, _: object) -> GoogleIdentityResult:
        return GoogleIdentityResult(
            subject=f"google:{self.email}",
            email=self.email,
            access_token="google-access-token",
            expires_in=3600,
            refresh_token="google-refresh-token",
        )


@dataclass
class FakeOAuthBroker:
    requests: list[OAuthTokenRequest]

    async def exchange(self, request: OAuthTokenRequest) -> OAuthTokenResponse:
        self.requests.append(request)
        return OAuthTokenResponse(
            access_token="refreshed-google-access-token",
            expires_in=3600,
            refresh_token=None,
        )


@dataclass
class FakeProductionProvider:
    events: list[EventProposal]
    fail: bool = False
    invalid_paid_output: bool = False
    unexpected_failure: bool = False
    calls: int = 0
    gate: asyncio.Event | None = None
    model: str = "google/gemini-3.1-flash-lite"
    ready: bool = True

    async def extract(self, request: ExtractionRequest) -> list[EventProposal]:
        return self.events

    async def extract_with_usage(
        self, request: ExtractionRequest
    ) -> ProviderExtractionResult:
        self.calls += 1
        if self.gate is not None:
            await self.gate.wait()
        if self.fail:
            raise ProviderUnavailableError("fake outage")
        if self.unexpected_failure:
            raise ValueError("private provider implementation failure")
        if self.invalid_paid_output:
            raise InvalidProviderOutputError(
                "fake invalid output",
                accounting=ProviderAccounting(
                    request_cost_usd=Decimal("0.0042"),
                    generation_id=f"generation-{self.calls}",
                    input_tokens=800,
                    output_tokens=40,
                ),
            )
        return ProviderExtractionResult(
            events=self.events,
            request_cost_usd=Decimal("0.0012"),
            generation_id=f"generation-{self.calls}",
            input_tokens=800,
            output_tokens=180,
        )

    async def key_status(self) -> ProviderKeyStatus:
        return ProviderKeyStatus(
            limit_usd=Decimal("25"),
            limit_remaining_usd=Decimal("25"),
            limit_reset="monthly",
        )


@dataclass
class V2Fixture:
    database: Database
    service: ProductionService
    provider: FakeProductionProvider
    client: httpx.AsyncClient
    private_key: X25519PrivateKey
    paddle_requests: list[dict[str, object]]
    billing: BillingService
    paddle_http: httpx.AsyncClient
    identity: FakeIdentity
    oauth_broker: FakeOAuthBroker


@pytest_asyncio.fixture
async def v2(tmp_path: Path) -> V2Fixture:
    database_url = os.environ.get(
        "SNAPCAL_TEST_DATABASE_URL",
        f"sqlite+aiosqlite:///{tmp_path / 'production.sqlite3'}",
    )
    settings = ProductionSettings(
        environment="test",
        database_url=database_url,
        session_signing_key=b"s" * 32,
        input_hmac_key=b"h" * 32,
        api_base_url="https://api.snapcal.test",
        web_base_url="https://www.snapcal.test",
        paddle_environment="sandbox",
        paddle_api_key="paddle-test-key",
        paddle_webhook_secret="paddle-test-secret",
        paddle_price_id="pri_test",
        provider_monthly_budget_usd=Decimal("25"),
    )
    database = Database(settings)
    async with database.engine.begin() as connection:
        await connection.run_sync(Base.metadata.drop_all)
        await connection.run_sync(Base.metadata.create_all)
    now = datetime.now(UTC)
    async with database.session() as session:
        async with session.begin():
            session.add_all(
                [
                    Plan(
                        code="free",
                        display_name="Free",
                        price_usd_cents=0,
                        monthly_quota=0,
                        per_minute_limit=0,
                        per_day_limit=0,
                        concurrent_limit=0,
                        accuracy_enabled=False,
                    ),
                    Plan(
                        code="pro_beta",
                        display_name="Pro Beta",
                        price_usd_cents=499,
                        monthly_quota=100,
                        per_minute_limit=5,
                        per_day_limit=30,
                        concurrent_limit=2,
                        accuracy_enabled=True,
                    ),
                    BetaInvite(
                        email_normalized="beta@example.com",
                        state="invited",
                        expires_at=now + timedelta(days=30),
                    ),
                ]
            )
    provider = FakeProductionProvider(events=[proposal(), proposal("Second Event")])
    identity = FakeIdentity()
    oauth_broker = FakeOAuthBroker(requests=[])
    service = ProductionService(
        settings=settings,
        database=database,
        identity=identity,
        provider=provider,
    )
    paddle_requests: list[dict[str, object]] = []

    def paddle_handler(request: httpx.Request) -> httpx.Response:
        paddle_requests.append(
            {
                "path": request.url.path,
                "authorization": request.headers.get("Authorization"),
                "body": json.loads(request.content or b"{}"),
            }
        )
        if request.url.path == "/transactions":
            return httpx.Response(
                201,
                json={"data": {"checkout": {"url": "https://checkout.paddle.test/txn"}}},
            )
        if request.url.path.endswith("/portal-sessions"):
            return httpx.Response(
                201,
                json={
                    "data": {
                        "urls": {
                            "general": {"overview": "https://portal.paddle.test/session"}
                        }
                    }
                },
            )
        return httpx.Response(404, json={"error": "not found"})

    paddle_http = httpx.AsyncClient(transport=httpx.MockTransport(paddle_handler))
    billing = BillingService(
        settings=settings,
        database=database,
        paddle=PaddleClient(
            api_key=settings.paddle_api_key,
            environment=settings.paddle_environment,
            price_id=settings.paddle_price_id,
            client=paddle_http,
        ),
    )
    app = create_app(
        provider=provider,
        oauth_broker=oauth_broker,
        production_service=service,
        billing_service=billing,
    )
    client = httpx.AsyncClient(
        transport=httpx.ASGITransport(app=app),
        base_url="https://api.snapcal.test",
    )
    fixture = V2Fixture(
        database=database,
        service=service,
        provider=provider,
        client=client,
        private_key=X25519PrivateKey.generate(),
        paddle_requests=paddle_requests,
        billing=billing,
        paddle_http=paddle_http,
        identity=identity,
        oauth_broker=oauth_broker,
    )
    yield fixture
    await client.aclose()
    await paddle_http.aclose()
    async with database.engine.begin() as connection:
        await connection.run_sync(Base.metadata.drop_all)
    await database.dispose()


async def sign_in(v2: V2Fixture) -> dict[str, object]:
    response = await v2.client.post(
        "/v2/auth/google/exchange",
        json={
            "authorization_code": "authorization-code",
            "pkce_verifier": "v" * 43,
            "redirect_uri": "http://127.0.0.1:49152/",
            "nonce": "n" * 32,
            "device_id": "test-device-1",
        },
    )
    assert response.status_code == 200, response.text
    return response.json()


async def activate_subscription(v2: V2Fixture, user_id: str) -> None:
    now = datetime.now(UTC)
    async with v2.database.session() as session:
        async with session.begin():
            session.add(
                Subscription(
                    user_id=uuid.UUID(user_id),
                    plan_code="pro_beta",
                    paddle_customer_id="ctm_test",
                    paddle_subscription_id="sub_test",
                    status="active",
                    product_id="pro_test",
                    price_id="pri_test",
                    current_period_start=now - timedelta(days=1),
                    current_period_end=now + timedelta(days=29),
                    last_event_occurred_at=now,
                )
            )


def extraction_form(v2: V2Fixture) -> tuple[dict[str, str], dict[str, tuple[str, bytes, str]]]:
    public_key = base64.urlsafe_b64encode(
        v2.private_key.public_key().public_bytes(
            encoding=serialization.Encoding.Raw,
            format=serialization.PublicFormat.Raw,
        )
    ).decode("ascii")
    metadata = {
        "schema_version": "2",
        "captured_at": "2026-07-15T09:24:13+07:00",
        "time_zone": "Asia/Ho_Chi_Minh",
        "locale": "vi_VN",
        "ocr_lines": [
            {"text": "Training 19/07/2026", "confidence": 0.99, "box": None},
            {"text": "Training 16/07/2026", "confidence": 0.99, "box": None},
        ],
        "retry_public_key": public_key,
    }
    return {"metadata": json.dumps(metadata)}, {"image": ("event.jpg", JPEG, "image/jpeg")}


@pytest.mark.asyncio
async def test_google_exchange_rotates_refresh_token_and_reuse_revokes_session(v2: V2Fixture) -> None:
    signed_in = await sign_in(v2)
    original = signed_in["session"]["refresh_token"]
    rotated = await v2.client.post(
        "/v2/auth/session/refresh", json={"refresh_token": original}
    )
    assert rotated.status_code == 200
    assert rotated.json()["refresh_token"] != original

    reused = await v2.client.post(
        "/v2/auth/session/refresh", json={"refresh_token": original}
    )
    assert reused.status_code == 401
    assert reused.json()["error"]["code"] == "refresh_token_reused"

    rejected = await v2.client.get(
        "/v2/me",
        headers={"Authorization": f"Bearer {rotated.json()['access_token']}"},
    )
    assert rejected.status_code == 401


@pytest.mark.asyncio
async def test_authenticated_google_refresh_is_transient_and_requires_session(
    v2: V2Fixture,
) -> None:
    request = {
        "client_id": "desktop-client-id",
        "grant_type": "refresh_token",
        "refresh_token": "keychain-only-google-refresh-token",
    }
    anonymous = await v2.client.post("/v2/auth/google/token", json=request)
    assert anonymous.status_code == 401
    assert v2.oauth_broker.requests == []

    signed_in = await sign_in(v2)
    response = await v2.client.post(
        "/v2/auth/google/token",
        headers={
            "Authorization": f"Bearer {signed_in['session']['access_token']}"
        },
        json=request,
    )
    assert response.status_code == 200, response.text
    assert response.json() == {
        "access_token": "refreshed-google-access-token",
        "expires_in": 3600.0,
        "refresh_token": None,
    }
    assert len(v2.oauth_broker.requests) == 1
    assert (
        v2.oauth_broker.requests[0].refresh_token
        == "keychain-only-google-refresh-token"
    )


@pytest.mark.asyncio
async def test_one_screenshot_with_multiple_events_consumes_one_unit_and_retries_encrypted(
    v2: V2Fixture,
) -> None:
    signed_in = await sign_in(v2)
    await activate_subscription(v2, signed_in["user_id"])
    access = signed_in["session"]["access_token"]
    data, files = extraction_form(v2)
    response = await v2.client.post(
        "/v2/extractions",
        headers={
            "Authorization": f"Bearer {access}",
            "Idempotency-Key": "multi-event-import-1",
        },
        data=data,
        files=files,
    )
    assert response.status_code == 200, response.text
    payload = response.json()
    assert len(payload["events"]) == 2
    assert payload["quota"]["used"] == 1
    assert payload["quota"]["remaining"] == 99

    retry = await v2.client.get(
        f"/v2/extractions/{payload['request_id']}",
        headers={"Authorization": f"Bearer {access}"},
    )
    assert retry.status_code == 200
    sealed = base64.urlsafe_b64decode(retry.json()["envelope_base64"])
    assert sealed[0] == 1
    ephemeral = __import__(
        "cryptography.hazmat.primitives.asymmetric.x25519", fromlist=["X25519PublicKey"]
    ).X25519PublicKey.from_public_bytes(sealed[1:33])
    shared_secret = v2.private_key.exchange(ephemeral)
    key = HKDF(
        algorithm=hashes.SHA256(),
        length=32,
        salt=None,
        info=b"snapcal-retry-v1",
    ).derive(shared_secret)
    plaintext = ChaCha20Poly1305(key).decrypt(sealed[33:45], sealed[45:], None)
    decrypted = json.loads(plaintext)
    assert len(decrypted["events"]) == 2
    assert decrypted["request_id"] == payload["request_id"]

    async with v2.database.session() as session:
        usage = await session.scalar(select(UsagePeriod))
        record = await session.scalar(select(ExtractionRequestRecord))
    assert usage is not None and usage.consumed_units == 1 and usage.reserved_units == 0
    assert record is not None
    assert record.encrypted_result_envelope is not None
    assert not hasattr(record, "image")
    assert not hasattr(record, "ocr_text")


@pytest.mark.asyncio
async def test_duplicate_idempotency_never_calls_provider_or_consumes_twice(v2: V2Fixture) -> None:
    signed_in = await sign_in(v2)
    await activate_subscription(v2, signed_in["user_id"])
    headers = {
        "Authorization": f"Bearer {signed_in['session']['access_token']}",
        "Idempotency-Key": "same-request-key",
    }
    data, files = extraction_form(v2)
    first = await v2.client.post("/v2/extractions", headers=headers, data=data, files=files)
    data, files = extraction_form(v2)
    second = await v2.client.post("/v2/extractions", headers=headers, data=data, files=files)
    assert first.status_code == 200
    assert second.status_code == 409
    assert second.json()["error"]["code"] == "request_complete"
    assert v2.provider.calls == 1
    async with v2.database.session() as session:
        usage = await session.scalar(select(UsagePeriod))
    assert usage is not None and usage.consumed_units == 1


@pytest.mark.asyncio
async def test_provider_failure_releases_reservation_and_consumes_no_quota(v2: V2Fixture) -> None:
    signed_in = await sign_in(v2)
    await activate_subscription(v2, signed_in["user_id"])
    v2.provider.fail = True
    data, files = extraction_form(v2)
    response = await v2.client.post(
        "/v2/extractions",
        headers={
            "Authorization": f"Bearer {signed_in['session']['access_token']}",
            "Idempotency-Key": "provider-failure-1",
        },
        data=data,
        files=files,
    )
    assert response.status_code == 503
    assert response.json()["error"]["code"] == "provider_unavailable"
    async with v2.database.session() as session:
        usage = await session.scalar(select(UsagePeriod))
        record = await session.scalar(select(ExtractionRequestRecord))
    assert usage is not None and usage.consumed_units == 0 and usage.reserved_units == 0
    assert record is not None and record.state == "failed" and record.quota_reserved is False


@pytest.mark.asyncio
async def test_invalid_paid_output_releases_quota_but_records_absorbed_cost(
    v2: V2Fixture,
) -> None:
    signed_in = await sign_in(v2)
    await activate_subscription(v2, signed_in["user_id"])
    v2.provider.invalid_paid_output = True
    data, files = extraction_form(v2)
    response = await v2.client.post(
        "/v2/extractions",
        headers={
            "Authorization": f"Bearer {signed_in['session']['access_token']}",
            "Idempotency-Key": "invalid-paid-output-1",
        },
        data=data,
        files=files,
    )
    assert response.status_code == 502
    assert response.json()["error"]["code"] == "invalid_provider_output"
    async with v2.database.session() as session:
        usage = await session.scalar(select(UsagePeriod))
        record = await session.scalar(select(ExtractionRequestRecord))
    assert usage is not None
    assert usage.consumed_units == 0 and usage.reserved_units == 0
    assert usage.actual_provider_cost_usd == Decimal("0.0042")
    assert record is not None
    assert record.provider_cost_usd == Decimal("0.0042")
    assert record.provider_generation_id == "generation-1"


@pytest.mark.asyncio
async def test_unexpected_provider_failure_cannot_leak_a_reservation(
    v2: V2Fixture,
) -> None:
    signed_in = await sign_in(v2)
    await activate_subscription(v2, signed_in["user_id"])
    v2.provider.unexpected_failure = True
    data, files = extraction_form(v2)
    response = await v2.client.post(
        "/v2/extractions",
        headers={
            "Authorization": f"Bearer {signed_in['session']['access_token']}",
            "Idempotency-Key": "unexpected-provider-failure-1",
        },
        data=data,
        files=files,
    )
    assert response.status_code == 500
    assert response.json()["error"]["code"] == "internal_error"
    assert "private provider implementation failure" not in response.text
    async with v2.database.session() as session:
        usage = await session.scalar(select(UsagePeriod))
        record = await session.scalar(select(ExtractionRequestRecord))
    assert usage is not None
    assert usage.consumed_units == 0 and usage.reserved_units == 0
    assert record is not None and record.state == "failed"


@pytest.mark.asyncio
async def test_local_or_unsigned_clients_cannot_reach_accuracy(v2: V2Fixture) -> None:
    data, files = extraction_form(v2)
    response = await v2.client.post(
        "/v2/extractions",
        headers={"Idempotency-Key": "unsigned-request"},
        data=data,
        files=files,
    )
    assert response.status_code == 401
    assert v2.provider.calls == 0


def paddle_event(
    *,
    event_id: str,
    user_id: str,
    occurred_at: datetime,
    status: str = "active",
    scheduled_change: dict[str, str] | None = None,
    include_billing_period: bool = True,
) -> bytes:
    return json.dumps(
        {
            "event_id": event_id,
            "event_type": "subscription.updated",
            "occurred_at": occurred_at.isoformat().replace("+00:00", "Z"),
            "data": {
                "id": "sub_test",
                "customer_id": "ctm_test",
                "status": status,
                "items": [{"price": {"id": "pri_test", "product_id": "pro_test"}}],
                "current_billing_period": (
                    {
                        "starts_at": (occurred_at - timedelta(days=1)).isoformat().replace("+00:00", "Z"),
                        "ends_at": (occurred_at + timedelta(days=29)).isoformat().replace("+00:00", "Z"),
                    }
                    if include_billing_period
                    else None
                ),
                "scheduled_change": scheduled_change,
                "custom_data": {"snapcal_user_id": user_id},
            },
        },
        separators=(",", ":"),
    ).encode("utf-8")


def paddle_signature(body: bytes, secret: str, now: datetime) -> str:
    timestamp = int(now.timestamp())
    digest = hmac.new(
        secret.encode("utf-8"),
        str(timestamp).encode("ascii") + b":" + body,
        hashlib.sha256,
    ).hexdigest()
    return f"ts={timestamp};h1={digest}"


@pytest.mark.asyncio
async def test_checkout_redirect_never_grants_access_and_signed_webhook_is_authoritative(
    v2: V2Fixture,
) -> None:
    signed_in = await sign_in(v2)
    access = signed_in["session"]["access_token"]
    headers = {"Authorization": f"Bearer {access}"}
    checkout = await v2.client.post("/v2/billing/checkout", headers=headers)
    assert checkout.status_code == 200
    assert checkout.json()["url"] == "https://checkout.paddle.test/txn"
    assert v2.paddle_requests[-1]["authorization"] == "Bearer paddle-test-key"
    assert v2.paddle_requests[-1]["body"]["custom_data"]["snapcal_user_id"] == signed_in["user_id"]
    assert v2.paddle_requests[-1]["body"]["checkout"]["url"] == "https://www.snapcal.test/checkout"
    assert "customer" not in v2.paddle_requests[-1]["body"]

    before_webhook = await v2.client.get("/v2/me", headers=headers)
    assert before_webhook.status_code == 200
    assert before_webhook.json()["plan"]["code"] == "free"
    assert before_webhook.json()["subscription_status"] == "none"

    now = datetime.now(UTC)
    body = paddle_event(event_id="evt_active", user_id=signed_in["user_id"], occurred_at=now)
    webhook = await v2.client.post(
        "/v2/webhooks/paddle",
        content=body,
        headers={
            "Content-Type": "application/json",
            "Paddle-Signature": paddle_signature(
                body, v2.service.settings.paddle_webhook_secret, now
            ),
        },
    )
    assert webhook.status_code == 200, webhook.text
    assert webhook.json() == {"accepted": True, "duplicate": False}

    after_webhook = await v2.client.get("/v2/me", headers=headers)
    assert after_webhook.json()["plan"]["code"] == "pro_beta"
    assert after_webhook.json()["quota"]["remaining"] == 100

    duplicate = await v2.client.post(
        "/v2/webhooks/paddle",
        content=body,
        headers={
            "Content-Type": "application/json",
            "Paddle-Signature": paddle_signature(
                body, v2.service.settings.paddle_webhook_secret, now
            ),
        },
    )
    assert duplicate.status_code == 200
    assert duplicate.json()["duplicate"] is True
    async with v2.database.session() as session:
        events = (await session.scalars(select(WebhookEvent))).all()
    assert len(events) == 1


@pytest.mark.asyncio
async def test_bad_and_out_of_order_webhooks_cannot_change_entitlement(v2: V2Fixture) -> None:
    signed_in = await sign_in(v2)
    access = signed_in["session"]["access_token"]
    now = datetime.now(UTC)
    active = paddle_event(event_id="evt_new", user_id=signed_in["user_id"], occurred_at=now)
    accepted = await v2.client.post(
        "/v2/webhooks/paddle",
        content=active,
        headers={"Paddle-Signature": paddle_signature(active, "paddle-test-secret", now)},
    )
    assert accepted.status_code == 200

    old = paddle_event(
        event_id="evt_old",
        user_id=signed_in["user_id"],
        occurred_at=now - timedelta(hours=1),
        status="paused",
    )
    ignored = await v2.client.post(
        "/v2/webhooks/paddle",
        content=old,
        headers={"Paddle-Signature": paddle_signature(old, "paddle-test-secret", now)},
    )
    assert ignored.status_code == 200
    me = await v2.client.get(
        "/v2/me", headers={"Authorization": f"Bearer {access}"}
    )
    assert me.json()["subscription_status"] == "active"

    bad = await v2.client.post(
        "/v2/webhooks/paddle",
        content=active,
        headers={"Paddle-Signature": "ts=0;h1=bad"},
    )
    assert bad.status_code == 401
    assert bad.json()["error"]["code"] == "invalid_webhook_signature"


@pytest.mark.asyncio
async def test_quota_denial_is_persisted_as_redacted_audit(v2: V2Fixture) -> None:
    signed_in = await sign_in(v2)
    await activate_subscription(v2, signed_in["user_id"])
    async with v2.database.session() as session:
        async with session.begin():
            plan = await session.get(Plan, "pro_beta")
            assert plan is not None
            plan.monthly_quota = 0

    data, files = extraction_form(v2)
    response = await v2.client.post(
        "/v2/extractions",
        headers={
            "Authorization": f"Bearer {signed_in['session']['access_token']}",
            "Idempotency-Key": "quota-denial-audit",
        },
        data=data,
        files=files,
    )
    assert response.status_code == 402
    assert response.json()["error"]["code"] == "quota_exhausted"
    assert v2.provider.calls == 0
    async with v2.database.session() as session:
        audits = (
            await session.scalars(
                select(AuditEvent).where(AuditEvent.action == "quota_denied")
            )
        ).all()
    assert [audit.reason_code for audit in audits] == ["quota_exhausted"]


@pytest.mark.asyncio
async def test_retry_result_expires_and_ciphertext_is_deleted(v2: V2Fixture) -> None:
    signed_in = await sign_in(v2)
    await activate_subscription(v2, signed_in["user_id"])
    access = signed_in["session"]["access_token"]
    data, files = extraction_form(v2)
    response = await v2.client.post(
        "/v2/extractions",
        headers={
            "Authorization": f"Bearer {access}",
            "Idempotency-Key": "expiring-retry-result",
        },
        data=data,
        files=files,
    )
    request_id = uuid.UUID(response.json()["request_id"])
    async with v2.database.session() as session:
        async with session.begin():
            record = await session.get(ExtractionRequestRecord, request_id)
            assert record is not None
            record.result_expires_at = datetime.now(UTC) - timedelta(seconds=1)

    expired = await v2.client.get(
        f"/v2/extractions/{request_id}",
        headers={"Authorization": f"Bearer {access}"},
    )
    assert expired.status_code == 410
    assert expired.json()["error"]["code"] == "result_expired"
    assert await v2.service.expire_retry_envelope(request_id) is True
    async with v2.database.session() as session:
        record = await session.get(ExtractionRequestRecord, request_id)
    assert record is not None
    assert record.encrypted_result_envelope is None
    assert record.result_expires_at is None


@pytest.mark.asyncio
async def test_rate_limit_stops_provider_before_sixth_call(v2: V2Fixture) -> None:
    signed_in = await sign_in(v2)
    await activate_subscription(v2, signed_in["user_id"])
    access = signed_in["session"]["access_token"]
    responses: list[httpx.Response] = []
    for index in range(6):
        data, files = extraction_form(v2)
        responses.append(
            await v2.client.post(
                "/v2/extractions",
                headers={
                    "Authorization": f"Bearer {access}",
                    "Idempotency-Key": f"minute-rate-{index}",
                },
                data=data,
                files=files,
            )
        )
    assert [response.status_code for response in responses] == [200] * 5 + [429]
    assert responses[-1].json()["error"]["code"] == "rate_limit_exceeded"
    assert v2.provider.calls == 5


@pytest.mark.asyncio
async def test_provider_budget_stops_call_before_invocation(v2: V2Fixture) -> None:
    signed_in = await sign_in(v2)
    await activate_subscription(v2, signed_in["user_id"])
    access = signed_in["session"]["access_token"]
    data, files = extraction_form(v2)
    first = await v2.client.post(
        "/v2/extractions",
        headers={
            "Authorization": f"Bearer {access}",
            "Idempotency-Key": "budget-first-call",
        },
        data=data,
        files=files,
    )
    assert first.status_code == 200
    async with v2.database.session() as session:
        async with session.begin():
            record = await session.scalar(select(ExtractionRequestRecord))
            assert record is not None
            record.provider_cost_usd = Decimal("25")

    data, files = extraction_form(v2)
    denied = await v2.client.post(
        "/v2/extractions",
        headers={
            "Authorization": f"Bearer {access}",
            "Idempotency-Key": "budget-denied-call",
        },
        data=data,
        files=files,
    )
    assert denied.status_code == 503
    assert denied.json()["error"]["code"] == "provider_budget_exhausted"
    assert v2.provider.calls == 1


@pytest.mark.asyncio
async def test_canceled_webhook_without_billing_period_revokes_access(v2: V2Fixture) -> None:
    signed_in = await sign_in(v2)
    access = signed_in["session"]["access_token"]
    headers = {"Authorization": f"Bearer {access}"}
    now = datetime.now(UTC)
    active = paddle_event(
        event_id="evt_before_cancel",
        user_id=signed_in["user_id"],
        occurred_at=now,
    )
    assert (
        await v2.client.post(
            "/v2/webhooks/paddle",
            content=active,
            headers={"Paddle-Signature": paddle_signature(active, "paddle-test-secret", now)},
        )
    ).status_code == 200
    canceled_at = now + timedelta(seconds=1)
    canceled = paddle_event(
        event_id="evt_canceled",
        user_id=signed_in["user_id"],
        occurred_at=canceled_at,
        status="canceled",
        include_billing_period=False,
    )
    assert (
        await v2.client.post(
            "/v2/webhooks/paddle",
            content=canceled,
            headers={
                "Paddle-Signature": paddle_signature(
                    canceled, "paddle-test-secret", canceled_at
                )
            },
        )
    ).status_code == 200
    me = await v2.client.get("/v2/me", headers=headers)
    assert me.json()["subscription_status"] == "canceled"
    assert me.json()["plan"]["code"] == "free"


@pytest.mark.asyncio
@pytest.mark.skipif(
    not os.environ.get("SNAPCAL_TEST_DATABASE_URL"),
    reason="PostgreSQL row-lock proof runs in CI",
)
async def test_postgres_row_lock_enforces_two_concurrent_requests(v2: V2Fixture) -> None:
    signed_in = await sign_in(v2)
    await activate_subscription(v2, signed_in["user_id"])
    access = signed_in["session"]["access_token"]
    v2.provider.gate = asyncio.Event()

    async def request(index: int) -> httpx.Response:
        data, files = extraction_form(v2)
        return await v2.client.post(
            "/v2/extractions",
            headers={
                "Authorization": f"Bearer {access}",
                "Idempotency-Key": f"concurrent-request-{index}",
            },
            data=data,
            files=files,
        )

    first = asyncio.create_task(request(1))
    second = asyncio.create_task(request(2))
    try:
        for _ in range(200):
            if v2.provider.calls >= 2:
                break
            await asyncio.sleep(0.01)
        assert v2.provider.calls == 2
        third = await request(3)
        assert third.status_code == 429
        assert third.json()["error"]["code"] == "concurrent_limit_exceeded"
    finally:
        v2.provider.gate.set()
    completed = await asyncio.gather(first, second)
    assert [response.status_code for response in completed] == [200, 200]
    async with v2.database.session() as session:
        usage = await session.scalar(select(UsagePeriod))
    assert usage is not None
    assert usage.consumed_units == 2
    assert usage.reserved_units == 0


@pytest.mark.asyncio
@pytest.mark.skipif(
    not os.environ.get("SNAPCAL_TEST_DATABASE_URL"),
    reason="The 50-user connection/load proof runs against PostgreSQL in CI",
)
async def test_fifty_users_share_bounded_pool_without_quota_duplication(v2: V2Fixture) -> None:
    now = datetime.now(UTC)
    session_records: list[tuple[uuid.UUID, uuid.UUID, str]] = []
    async with v2.database.session() as session:
        async with session.begin():
            for index in range(50):
                user = User(
                    email_normalized=f"load-{index}@example.com",
                    google_subject=f"google-load-{index}",
                )
                session.add(user)
                await session.flush()
                device = f"load-device-{index}"
                auth = AuthSession(
                    user_id=user.id,
                    device_identifier=device,
                    refresh_token_hash=hashlib.sha256(device.encode()).hexdigest(),
                    expires_at=now + timedelta(days=1),
                )
                session.add(auth)
                session.add(
                    BetaInvite(
                        email_normalized=user.email_normalized,
                        state="activated",
                        activation_user_id=user.id,
                        expires_at=now + timedelta(days=30),
                        activated_at=now,
                    )
                )
                session.add(
                    Subscription(
                        user_id=user.id,
                        plan_code="pro_beta",
                        paddle_customer_id=f"ctm_load_{index}",
                        paddle_subscription_id=f"sub_load_{index}",
                        status="active",
                        product_id="pro_test",
                        price_id="pri_test",
                        current_period_start=now - timedelta(days=1),
                        current_period_end=now + timedelta(days=29),
                        last_event_occurred_at=now,
                    )
                )
                await session.flush()
                session_records.append((user.id, auth.id, device))

    async def request(index: int, token: str) -> httpx.Response:
        data, files = extraction_form(v2)
        return await v2.client.post(
            "/v2/extractions",
            headers={
                "Authorization": f"Bearer {token}",
                "Idempotency-Key": f"load-request-{index}",
            },
            data=data,
            files=files,
        )

    tokens = [
        v2.service.tokens.access_token(
            user_id=user_id,
            session_id=session_id,
            device_id=device,
        )[0]
        for user_id, session_id, device in session_records
    ]
    responses = await asyncio.gather(
        *(request(index, token) for index, token in enumerate(tokens))
    )
    assert all(response.status_code == 200 for response in responses)
    assert v2.provider.calls == 50
    async with v2.database.session() as session:
        usages = (await session.scalars(select(UsagePeriod))).all()
    assert len(usages) == 50
    assert sum(period.consumed_units for period in usages) == 50
    assert sum(period.reserved_units for period in usages) == 0
