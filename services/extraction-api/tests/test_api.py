from __future__ import annotations

import base64
from dataclasses import dataclass

from fastapi.testclient import TestClient

from app.contracts import EventProposal, ExtractionRequest
from app.main import create_app
from app.oauth_broker import OAuthBrokerUnavailableError, OAuthClientMismatchError
from app.provider import InvalidProviderOutputError, ProviderUnavailableError


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

    async def extract(self, request: ExtractionRequest) -> EventProposal:
        self.received = request
        return self.proposal


@dataclass
class FailingProvider:
    error: Exception
    model: str = "google/gemini-3.1-flash-lite"
    ready: bool = True

    async def extract(self, request: ExtractionRequest) -> EventProposal:
        raise self.error


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
    assert body["event"]["title"]["value"] == "Agentic AI Build Week"
    assert body["event"]["start"]["date"] == "2026-07-08"
    assert body["event"]["end"]["date"] == "2026-07-12"
    assert body["event"]["is_all_day"] is True
    assert provider.received is not None
    assert provider.received.decoded_image() == JPEG


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
