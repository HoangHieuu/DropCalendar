from __future__ import annotations

import base64
from dataclasses import dataclass, field
from decimal import Decimal

import pytest

from fastapi.testclient import TestClient

from app.contracts import EventProposal, ExtractionRequest
from app.benchmark import BenchmarkBudget, BenchmarkConfigurationError
from app.main import create_app
from app.oauth_broker import OAuthBrokerUnavailableError, OAuthClientMismatchError
from app.provider import (
    InvalidProviderOutputError,
    ProviderAccounting,
    ProviderExtractionResult,
    ProviderKeyStatus,
    ProviderUnavailableError,
)


JPEG = b"\xff\xd8\xff\xe0snapcal-test"


def valid_payload() -> dict:
    return {
        "schema_version": "1",
        "image_base64": base64.b64encode(JPEG).decode("ascii"),
        "mime_type": "image/jpeg",
        "captured_at": "2026-07-13T20:39:27+07:00",
        "time_zone": "Asia/Ho_Chi_Minh",
        "locale": "en_VN",
        "ocr_lines": [
            {
                "text": "AGENTIC AI BUILD WEEK",
                "confidence": 0.98,
                "box": {"x": 0.2, "y": 0.55, "width": 0.58, "height": 0.22},
            },
            {"text": "July 8 - July 12, 2026", "confidence": 0.96, "box": None},
        ],
    }


def valid_proposal() -> EventProposal:
    return EventProposal.model_validate(
        {
            "title": {
                "value": "Agentic AI Build Week",
                "evidence_text": "AGENTIC AI BUILD WEEK",
                "confidence": 0.98,
                "is_inferred": False,
            },
            "start": {
                "date": "2026-07-08",
                "time": None,
                "evidence_text": "July 8 - July 12, 2026",
                "confidence": 0.96,
                "is_inferred": False,
            },
            "end": {
                "date": "2026-07-12",
                "time": None,
                "evidence_text": "July 8 - July 12, 2026",
                "confidence": 0.96,
                "is_inferred": False,
            },
            "location": {
                "value": "Ho Chi Minh, Vietnam",
                "evidence_text": "Ho Chi Minh, Vietnam",
                "confidence": 0.95,
                "is_inferred": False,
            },
            "description": {
                "value": "5 Days (Workshops + Hackathon)",
                "evidence_text": "5 Days (Workshops + Hackathon)",
                "confidence": 0.92,
                "is_inferred": False,
            },
            "is_all_day": True,
            "ambiguities": [],
        }
    )


@dataclass
class FakeProvider:
    proposal: EventProposal
    model: str = "google/gemini-3.1-flash-lite"
    ready: bool = True
    received: ExtractionRequest | None = None

    async def extract(self, request: ExtractionRequest) -> list[EventProposal]:
        self.received = request
        return [self.proposal]


@dataclass
class FakeBenchmarkProvider:
    proposal: EventProposal
    costs: list[Decimal]
    key: ProviderKeyStatus = field(default_factory=lambda: ProviderKeyStatus(
        limit_usd=Decimal("5"),
        limit_remaining_usd=Decimal("5"),
        limit_reset=None,
    ))
    model: str = "google/gemini-3.1-flash-lite"
    ready: bool = True
    benchmark_calls: int = 0

    async def extract(self, request: ExtractionRequest) -> list[EventProposal]:
        return [self.proposal]

    async def extract_with_usage(
        self, request: ExtractionRequest
    ) -> ProviderExtractionResult:
        cost = self.costs[self.benchmark_calls]
        self.benchmark_calls += 1
        return ProviderExtractionResult(
            events=[self.proposal],
            request_cost_usd=cost,
            generation_id=f"gen-{self.benchmark_calls}",
        )

    async def key_status(self) -> ProviderKeyStatus:
        return self.key


@dataclass
class InvalidBenchmarkProvider:
    model: str = "google/gemini-3.1-flash-lite"
    ready: bool = True

    async def extract(self, request: ExtractionRequest) -> list[EventProposal]:
        return [valid_proposal()]

    async def extract_with_usage(
        self, request: ExtractionRequest
    ) -> ProviderExtractionResult:
        raise InvalidProviderOutputError(
            "invalid event proposal",
            accounting=ProviderAccounting(
                request_cost_usd=Decimal("0.0042"),
                generation_id="invalid-generation",
            ),
        )

    async def key_status(self) -> ProviderKeyStatus:
        return ProviderKeyStatus(
            limit_usd=Decimal("5"),
            limit_remaining_usd=Decimal("5"),
            limit_reset=None,
        )


@dataclass
class FailingProvider:
    error: Exception
    model: str = "google/gemini-3.1-flash-lite"
    ready: bool = True

    async def extract(self, request: ExtractionRequest) -> list[EventProposal]:
        raise self.error


@dataclass
class FakeMultiProvider:
    proposals: list[EventProposal]
    model: str = "google/gemini-3.1-flash-lite"
    ready: bool = True

    async def extract(self, request: ExtractionRequest) -> list[EventProposal]:
        return self.proposals


@dataclass
class FakeOAuthBroker:
    error: Exception | None = None

    async def exchange(self, request):
        if self.error:
            raise self.error
        return {
            "access_token": "broker-access-token",
            "expires_in": 3_600,
            "refresh_token": "broker-refresh-token",
        }


def test_health_discloses_readiness_without_credentials() -> None:
    provider = FakeProvider(valid_proposal())
    response = TestClient(create_app(provider)).get("/health")

    assert response.status_code == 200
    assert response.json() == {
        "status": "ok",
        "provider": "openrouter",
        "model": "google/gemini-3.1-flash-lite",
        "ready": True,
    }


def test_extract_returns_strict_all_day_range_and_passes_bounded_input() -> None:
    provider = FakeProvider(valid_proposal())
    response = TestClient(create_app(provider)).post("/v1/extract", json=valid_payload())

    assert response.status_code == 200
    body = response.json()
    assert body["schema_version"] == "2"
    assert len(body["events"]) == 1
    assert body["events"][0]["title"]["value"] == "Agentic AI Build Week"
    assert body["events"][0]["start"]["date"] == "2026-07-08"
    assert body["events"][0]["end"]["date"] == "2026-07-12"
    assert body["events"][0]["is_all_day"] is True
    assert "usage" not in body
    assert provider.received is not None
    assert provider.received.decoded_image() == JPEG


def test_extract_returns_multiple_events_in_provider_order() -> None:
    first = valid_proposal()
    second_data = first.model_dump(mode="json")
    second_data["title"]["value"] = "Agentic AI Demo Day"
    second_data["start"]["date"] = "2026-07-13"
    second_data["start"]["evidence_text"] = "July 13, 2026"
    second_data["end"]["date"] = "2026-07-13"
    second_data["end"]["evidence_text"] = "July 13, 2026"
    second = EventProposal.model_validate(second_data)

    response = TestClient(create_app(FakeMultiProvider([first, second]))).post(
        "/v1/extract",
        json=valid_payload(),
    )

    assert response.status_code == 200
    assert response.json()["schema_version"] == "2"
    assert [event["title"]["value"] for event in response.json()["events"]] == [
        "Agentic AI Build Week",
        "Agentic AI Demo Day",
    ]


def test_benchmark_endpoint_is_disabled_by_default() -> None:
    response = TestClient(create_app(FakeProvider(valid_proposal()))).post(
        "/v1/benchmark/extract",
        json=valid_payload(),
    )

    assert response.status_code == 404


def test_benchmark_preflight_and_extract_report_cumulative_cost() -> None:
    provider = FakeBenchmarkProvider(
        valid_proposal(),
        costs=[Decimal("0.01"), Decimal("0.02")],
    )
    client = TestClient(
        create_app(provider, benchmark_budget=BenchmarkBudget("0.05"))
    )

    preflight = client.get("/v1/benchmark/preflight")
    first = client.post("/v1/benchmark/extract", json=valid_payload())
    second = client.post("/v1/benchmark/extract", json=valid_payload())

    assert preflight.status_code == 200
    assert preflight.json()["budget_ceiling_usd"] == 0.05
    assert preflight.json()["provider_key_limit_usd"] == 5.0
    assert first.status_code == 200
    assert first.json()["usage"] == {
        "request_cost_usd": 0.01,
        "cumulative_cost_usd": 0.01,
        "budget_remaining_usd": 0.04,
        "request_count": 1,
    }
    assert second.json()["usage"]["cumulative_cost_usd"] == 0.03
    assert second.json()["usage"]["budget_remaining_usd"] == 0.02


def test_benchmark_records_cost_for_invalid_paid_output() -> None:
    client = TestClient(
        create_app(InvalidBenchmarkProvider(), benchmark_budget=BenchmarkBudget("0.05"))
    )

    response = client.post("/v1/benchmark/extract", json=valid_payload())
    status = client.get("/v1/benchmark/status")

    assert response.status_code == 502
    assert response.json()["detail"]["code"] == "invalid_provider_output"
    assert status.json()["usage"] == {
        "request_cost_usd": 0.0,
        "cumulative_cost_usd": 0.0042,
        "budget_remaining_usd": 0.0458,
        "request_count": 1,
    }


def test_benchmark_refuses_requests_after_budget_is_exhausted() -> None:
    provider = FakeBenchmarkProvider(
        valid_proposal(),
        costs=[Decimal("0.01"), Decimal("0.01")],
    )
    client = TestClient(
        create_app(provider, benchmark_budget=BenchmarkBudget("0.01"))
    )

    assert client.post("/v1/benchmark/extract", json=valid_payload()).status_code == 200
    exhausted = client.post("/v1/benchmark/extract", json=valid_payload())

    assert exhausted.status_code == 402
    assert exhausted.json()["detail"]["code"] == "benchmark_budget_exhausted"
    assert provider.benchmark_calls == 1


def test_benchmark_preflight_rejects_key_limit_above_five_dollars() -> None:
    provider = FakeBenchmarkProvider(
        valid_proposal(),
        costs=[Decimal("0.01")],
        key=ProviderKeyStatus(
            limit_usd=Decimal("10"),
            limit_remaining_usd=Decimal("10"),
            limit_reset=None,
        ),
    )
    client = TestClient(
        create_app(provider, benchmark_budget=BenchmarkBudget("5"))
    )

    response = client.get("/v1/benchmark/preflight")

    assert response.status_code == 503
    assert response.json()["detail"]["code"] == "benchmark_preflight_failed"


def test_benchmark_configuration_rejects_budget_above_authorized_ceiling() -> None:
    with pytest.raises(BenchmarkConfigurationError, match="cannot exceed"):
        BenchmarkBudget("5.01")


def test_rejects_invalid_base64_and_mismatched_mime_type() -> None:
    provider = FakeProvider(valid_proposal())
    client = TestClient(create_app(provider))
    payload = valid_payload()
    payload["image_base64"] = "not-base64"
    assert client.post("/v1/extract", json=payload).status_code == 422

    payload = valid_payload()
    payload["mime_type"] = "image/png"
    assert client.post("/v1/extract", json=payload).status_code == 422


def test_provider_failures_are_redacted_stable_errors() -> None:
    unavailable = TestClient(create_app(FailingProvider(ProviderUnavailableError("missing key"))))
    response = unavailable.post("/v1/extract", json=valid_payload())
    assert response.status_code == 503
    assert response.json()["detail"]["code"] == "provider_unavailable"
    assert "image_base64" not in response.text

    invalid = TestClient(create_app(FailingProvider(InvalidProviderOutputError("bad provider body"))))
    response = invalid.post("/v1/extract", json=valid_payload())
    assert response.status_code == 502
    assert response.json()["detail"]["code"] == "invalid_provider_output"
    assert "bad provider body" not in response.text


def test_contract_rejects_invented_date_evidence_and_reversed_range() -> None:
    data = valid_proposal().model_dump(mode="json")
    data["start"]["evidence_text"] = None
    try:
        EventProposal.model_validate(data)
    except ValueError as error:
        assert "requires evidence_text" in str(error)
    else:
        raise AssertionError("Expected missing date evidence to fail")

    data = valid_proposal().model_dump(mode="json")
    data["end"]["date"] = "2026-07-07"
    try:
        EventProposal.model_validate(data)
    except ValueError as error:
        assert "cannot precede start" in str(error)
    else:
        raise AssertionError("Expected reversed range to fail")


def test_oauth_token_endpoint_returns_only_bounded_token_fields() -> None:
    client = TestClient(create_app(FakeProvider(valid_proposal()), FakeOAuthBroker()))
    response = client.post(
        "/v1/google-oauth/token",
        json={
            "client_id": "desktop-client-id",
            "grant_type": "authorization_code",
            "code": "authorization-code",
            "code_verifier": "v" * 43,
            "redirect_uri": "http://127.0.0.1:49152",
        },
    )

    assert response.status_code == 200
    assert response.json() == {
        "access_token": "broker-access-token",
        "expires_in": 3_600.0,
        "refresh_token": "broker-refresh-token",
    }
    assert "client_secret" not in response.text


def test_oauth_token_endpoint_rejects_non_loopback_redirect_and_redacts_failures() -> None:
    provider = FakeProvider(valid_proposal())
    client = TestClient(create_app(provider, FakeOAuthBroker()))
    payload = {
        "client_id": "desktop-client-id",
        "grant_type": "authorization_code",
        "code": "private-authorization-code",
        "code_verifier": "v" * 43,
        "redirect_uri": "https://attacker.example/callback",
    }
    response = client.post("/v1/google-oauth/token", json=payload)
    assert response.status_code == 422
    assert "private-authorization-code" not in response.text

    unavailable = TestClient(create_app(provider, FakeOAuthBroker(
        OAuthBrokerUnavailableError("private credential path")
    )))
    response = unavailable.post(
        "/v1/google-oauth/token",
        json={
            "client_id": "desktop-client-id",
            "grant_type": "refresh_token",
            "refresh_token": "private-refresh-token",
        },
    )
    assert response.status_code == 503
    assert response.json()["detail"]["code"] == "oauth_broker_unavailable"
    assert "private" not in response.text

    mismatch = TestClient(create_app(provider, FakeOAuthBroker(
        OAuthClientMismatchError("private client metadata")
    )))
    response = mismatch.post(
        "/v1/google-oauth/token",
        json={
            "client_id": "desktop-client-id",
            "grant_type": "refresh_token",
            "refresh_token": "private-refresh-token",
        },
    )
    assert response.status_code == 400
    assert response.json()["detail"]["code"] == "oauth_client_mismatch"
    assert "private-refresh-token" not in response.text
