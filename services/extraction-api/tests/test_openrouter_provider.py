from __future__ import annotations

import base64
import asyncio
import json
from decimal import Decimal

import httpx
import pytest

from app.contracts import EventProposal, ExtractionRequest
from app.provider import (
    InvalidProviderOutputError,
    OpenRouterProvider,
    ProviderRejectedError,
    ProviderUnavailableError,
    ProviderUsageUnavailableError,
)


def extraction_request() -> ExtractionRequest:
    image = b"\xff\xd8\xff\xe0snapcal-provider-test"
    return ExtractionRequest.model_validate(
        {
            "schema_version": "1",
            "image_base64": base64.b64encode(image).decode("ascii"),
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
                {"text": "July 8 - July 12, 2026", "confidence": 0.96},
            ],
        }
    )


def proposal_json() -> str:
    proposal = EventProposal.model_validate(
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
    return json.dumps({"events": [proposal.model_dump(mode="json")]})


def test_openrouter_request_keeps_key_server_side_and_uses_strict_multimodal_schema() -> None:
    captured: dict[str, object] = {}

    def handler(request: httpx.Request) -> httpx.Response:
        captured["authorization"] = request.headers.get("Authorization")
        captured["referer"] = request.headers.get("HTTP-Referer")
        captured["title"] = request.headers.get("X-OpenRouter-Title")
        captured["body"] = json.loads(request.content)
        return httpx.Response(
            200,
            json={"choices": [{"message": {"content": proposal_json()}}]},
        )

    provider = OpenRouterProvider(
        api_key="test-openrouter-key",
        model="google/gemini-3.1-flash-lite",
        http_referer="https://snapcal.example",
        app_name="SnapCal",
        transport=httpx.MockTransport(handler),
    )
    result = asyncio.run(provider.extract(extraction_request()))

    body = captured["body"]
    assert isinstance(body, dict)
    assert body["messages"][0]["role"] == "system"
    content = body["messages"][1]["content"]
    assert captured["authorization"] == "Bearer test-openrouter-key"
    assert captured["referer"] == "https://snapcal.example"
    assert captured["title"] == "SnapCal"
    assert body["model"] == "google/gemini-3.1-flash-lite"
    assert content[1]["type"] == "image_url"
    assert content[1]["image_url"]["url"].startswith("data:image/jpeg;base64,")
    assert body["response_format"]["type"] == "json_schema"
    assert body["response_format"]["json_schema"]["strict"] is True
    event_array = body["response_format"]["json_schema"]["schema"]["properties"]["events"]
    assert event_array["minItems"] == 1
    assert event_array["maxItems"] == 10
    assert body["provider"]["require_parameters"] is True
    assert body["provider"]["allow_fallbacks"] is True
    assert body["provider"]["data_collection"] == "deny"
    assert body["provider"]["zdr"] is True
    assert body["provider"]["max_price"] == {"prompt": 0.30, "completion": 1.80}
    assert body["usage"] == {"include": True}
    assert body["max_completion_tokens"] == 2_500
    assert len(result) == 1
    assert result[0].title.value == "Agentic AI Build Week"


@pytest.mark.parametrize(
    ("status", "error_type"),
    [(401, ProviderRejectedError), (429, ProviderUnavailableError), (503, ProviderUnavailableError)],
)
def test_openrouter_status_errors_are_stable_and_redacted(
    status: int,
    error_type: type[Exception],
) -> None:
    secret_body = {"error": {"message": "private provider diagnostic"}}
    provider = OpenRouterProvider(
        api_key="secret-that-must-not-leak",
        model="google/gemini-3.1-flash-lite",
        transport=httpx.MockTransport(
            lambda _: httpx.Response(status, json=secret_body)
        ),
    )

    with pytest.raises(error_type) as caught:
        asyncio.run(provider.extract(extraction_request()))
    assert "private provider diagnostic" not in str(caught.value)
    assert "secret-that-must-not-leak" not in str(caught.value)


def test_openrouter_rejects_malformed_success_envelope() -> None:
    provider = OpenRouterProvider(
        api_key="test-key",
        model="google/gemini-3.1-flash-lite",
        transport=httpx.MockTransport(
            lambda _: httpx.Response(200, json={"choices": []})
        ),
    )

    with pytest.raises(InvalidProviderOutputError):
        asyncio.run(provider.extract(extraction_request()))


def test_openrouter_rejects_empty_multiple_event_proposal() -> None:
    provider = OpenRouterProvider(
        api_key="test-key",
        model="google/gemini-3.1-flash-lite",
        transport=httpx.MockTransport(
            lambda _: httpx.Response(
                200,
                json={"choices": [{"message": {"content": '{"events":[]}'}}]},
            )
        ),
    )

    with pytest.raises(InvalidProviderOutputError):
        asyncio.run(provider.extract(extraction_request()))


def test_openrouter_requires_https_endpoint() -> None:
    with pytest.raises(ProviderUnavailableError):
        OpenRouterProvider(
            api_key="test-key",
            model="google/gemini-3.1-flash-lite",
            base_url="http://openrouter.example/api/v1",
        )


def test_openrouter_returns_non_streaming_usage_cost() -> None:
    provider = OpenRouterProvider(
        api_key="test-key",
        model="google/gemini-3.1-flash-lite",
        transport=httpx.MockTransport(
            lambda _: httpx.Response(
                200,
                json={
                    "id": "gen-direct-cost",
                    "choices": [{"message": {"content": proposal_json()}}],
                    "usage": {"cost": 0.0125},
                },
            )
        ),
    )

    result = asyncio.run(provider.extract_with_usage(extraction_request()))

    assert result.generation_id == "gen-direct-cost"
    assert result.request_cost_usd == Decimal("0.0125")


def test_openrouter_falls_back_to_generation_metadata_for_cost() -> None:
    paths: list[str] = []

    def handler(request: httpx.Request) -> httpx.Response:
        paths.append(request.url.path)
        if request.url.path.endswith("/chat/completions"):
            return httpx.Response(
                200,
                json={
                    "id": "gen-fallback-cost",
                    "choices": [{"message": {"content": proposal_json()}}],
                    "usage": {"prompt_tokens": 100},
                },
            )
        assert request.url.params["id"] == "gen-fallback-cost"
        return httpx.Response(200, json={"data": {"total_cost": 0.021}})

    provider = OpenRouterProvider(
        api_key="test-key",
        model="google/gemini-3.1-flash-lite",
        transport=httpx.MockTransport(handler),
    )

    result = asyncio.run(provider.extract_with_usage(extraction_request()))

    assert result.request_cost_usd == Decimal("0.021")
    assert paths == ["/api/v1/chat/completions", "/api/v1/generation"]


def test_openrouter_fails_closed_when_cost_is_unavailable() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        if request.url.path.endswith("/chat/completions"):
            return httpx.Response(
                200,
                json={
                    "id": "gen-no-cost",
                    "choices": [{"message": {"content": proposal_json()}}],
                },
            )
        return httpx.Response(200, json={"data": {"total_cost": None}})

    provider = OpenRouterProvider(
        api_key="test-key",
        model="google/gemini-3.1-flash-lite",
        transport=httpx.MockTransport(handler),
    )

    with pytest.raises(ProviderUsageUnavailableError):
        asyncio.run(provider.extract_with_usage(extraction_request()))


def test_openrouter_preserves_cost_when_paid_output_is_invalid() -> None:
    provider = OpenRouterProvider(
        api_key="test-key",
        model="google/gemini-3.1-flash-lite",
        transport=httpx.MockTransport(
            lambda _: httpx.Response(
                200,
                json={
                    "id": "gen-invalid-output",
                    "choices": [{"message": {"content": '{"events":[]}'}}],
                    "usage": {
                        "cost": 0.0042,
                        "prompt_tokens": 800,
                        "completion_tokens": 40,
                    },
                },
            )
        ),
    )

    with pytest.raises(InvalidProviderOutputError) as caught:
        asyncio.run(provider.extract_with_usage(extraction_request()))

    assert caught.value.accounting is not None
    assert caught.value.accounting.request_cost_usd == Decimal("0.0042")
    assert caught.value.accounting.generation_id == "gen-invalid-output"
    assert caught.value.accounting.input_tokens == 800
    assert caught.value.accounting.output_tokens == 40


def test_openrouter_reads_current_key_spending_limit() -> None:
    provider = OpenRouterProvider(
        api_key="test-key",
        model="google/gemini-3.1-flash-lite",
        transport=httpx.MockTransport(
            lambda request: httpx.Response(
                200,
                json={
                    "data": {
                        "limit": 5,
                        "limit_remaining": 4.75,
                        "limit_reset": "monthly",
                    }
                },
            )
        ),
    )

    status = asyncio.run(provider.key_status())

    assert status.limit_usd == Decimal("5")
    assert status.limit_remaining_usd == Decimal("4.75")
    assert status.limit_reset == "monthly"
