from __future__ import annotations

import json
from dataclasses import dataclass
from decimal import Decimal, InvalidOperation
from typing import Any, Protocol
from urllib.parse import urlparse

import httpx

from .contracts import EventProposal, EventProposalSet, ExtractionRequest


class ProviderUnavailableError(RuntimeError):
    pass


class ProviderRejectedError(RuntimeError):
    pass


class InvalidProviderOutputError(RuntimeError):
    pass


class ProviderUsageUnavailableError(RuntimeError):
    pass


@dataclass(frozen=True)
class ProviderExtractionResult:
    events: list[EventProposal]
    request_cost_usd: Decimal
    generation_id: str


@dataclass(frozen=True)
class ProviderKeyStatus:
    limit_usd: Decimal | None
    limit_remaining_usd: Decimal | None
    limit_reset: str | None


class ExtractionProvider(Protocol):
    model: str

    @property
    def ready(self) -> bool: ...

    async def extract(self, request: ExtractionRequest) -> list[EventProposal]: ...


class BenchmarkExtractionProvider(ExtractionProvider, Protocol):
    async def extract_with_usage(
        self, request: ExtractionRequest
    ) -> ProviderExtractionResult: ...

    async def key_status(self) -> ProviderKeyStatus: ...


@dataclass(frozen=True)
class UnavailableOpenRouterProvider:
    model: str

    @property
    def ready(self) -> bool:
        return False

    async def extract(self, request: ExtractionRequest) -> list[EventProposal]:
        raise ProviderUnavailableError("OpenRouter authorization is not configured")


class OpenRouterProvider:
    def __init__(
        self,
        api_key: str,
        model: str,
        base_url: str = "https://openrouter.ai/api/v1",
        http_referer: str | None = None,
        app_name: str | None = None,
        transport: httpx.AsyncBaseTransport | None = None,
    ) -> None:
        key = api_key.strip()
        selected_model = model.strip()
        normalized_base_url = base_url.rstrip("/")
        parsed = urlparse(normalized_base_url)
        if not key or not selected_model:
            raise ProviderUnavailableError("OpenRouter configuration is incomplete")
        if parsed.scheme != "https" or not parsed.netloc:
            raise ProviderUnavailableError("OpenRouter endpoint must use HTTPS")

        self.model = selected_model
        self._api_key = key
        self._completion_endpoint = f"{normalized_base_url}/chat/completions"
        self._generation_endpoint = f"{normalized_base_url}/generation"
        self._key_endpoint = f"{normalized_base_url}/key"
        self._http_referer = (http_referer or "").strip()
        self._app_name = (app_name or "").strip()
        self._transport = transport

    @property
    def ready(self) -> bool:
        return True

    async def extract(self, request: ExtractionRequest) -> list[EventProposal]:
        envelope = await self._completion_envelope(request)
        return self._events_from_envelope(envelope)

    async def extract_with_usage(
        self, request: ExtractionRequest
    ) -> ProviderExtractionResult:
        envelope = await self._completion_envelope(request)
        events = self._events_from_envelope(envelope)
        generation_id = envelope.get("id")
        if not isinstance(generation_id, str) or not generation_id.strip():
            raise ProviderUsageUnavailableError(
                "OpenRouter response omitted the generation identifier"
            )
        try:
            request_cost = _optional_nonnegative_decimal(
                (envelope.get("usage") or {}).get("cost")
                if isinstance(envelope.get("usage"), dict)
                else None
            )
        except (TypeError, ValueError, InvalidOperation) as error:
            raise ProviderUsageUnavailableError(
                "OpenRouter response contained invalid usage cost"
            ) from error
        if request_cost is None:
            request_cost = await self._generation_cost(generation_id.strip())
        return ProviderExtractionResult(
            events=events,
            request_cost_usd=request_cost,
            generation_id=generation_id.strip(),
        )

    async def key_status(self) -> ProviderKeyStatus:
        response = await self._send("GET", self._key_endpoint)
        self._raise_for_status(response)
        try:
            envelope = response.json()
            data = envelope["data"]
            if not isinstance(data, dict):
                raise TypeError("key data must be an object")
            limit = _optional_nonnegative_decimal(data.get("limit"))
            remaining = _optional_nonnegative_decimal(data.get("limit_remaining"))
            limit_reset = data.get("limit_reset")
            if limit_reset is not None and not isinstance(limit_reset, str):
                raise TypeError("limit reset must be a string or null")
            return ProviderKeyStatus(
                limit_usd=limit,
                limit_remaining_usd=remaining,
                limit_reset=limit_reset,
            )
        except (KeyError, TypeError, ValueError, InvalidOperation) as error:
            raise InvalidProviderOutputError(
                "OpenRouter key status failed contract validation"
            ) from error

    async def _completion_envelope(
        self, request: ExtractionRequest
    ) -> dict[str, Any]:
        response = await self._send(
            "POST",
            self._completion_endpoint,
            json_body=self._request_payload(request),
        )
        self._raise_for_status(response)
        try:
            envelope = response.json()
            if not isinstance(envelope, dict):
                raise TypeError("completion response must be an object")
            return envelope
        except (json.JSONDecodeError, TypeError, ValueError) as error:
            raise InvalidProviderOutputError(
                "OpenRouter output failed contract validation"
            ) from error

    def _events_from_envelope(self, envelope: dict[str, Any]) -> list[EventProposal]:
        try:
            output_text = envelope["choices"][0]["message"]["content"]
            if not isinstance(output_text, str) or not output_text.strip():
                raise ValueError("missing structured content")
            payload = json.loads(output_text)
            return EventProposalSet.model_validate(payload).events
        except (json.JSONDecodeError, KeyError, IndexError, TypeError, ValueError) as error:
            raise InvalidProviderOutputError(
                "OpenRouter output failed contract validation"
            ) from error

    async def _generation_cost(self, generation_id: str) -> Decimal:
        response = await self._send(
            "GET",
            self._generation_endpoint,
            query={"id": generation_id},
        )
        self._raise_for_status(response)
        try:
            envelope = response.json()
            data = envelope["data"]
            if not isinstance(data, dict):
                raise TypeError("generation data must be an object")
            cost = _optional_nonnegative_decimal(data.get("total_cost"))
            if cost is None:
                cost = _optional_nonnegative_decimal(data.get("usage"))
            if cost is None:
                raise ValueError("generation cost is absent")
            return cost
        except (KeyError, TypeError, ValueError, InvalidOperation) as error:
            raise ProviderUsageUnavailableError(
                "OpenRouter generation cost is unavailable"
            ) from error

    async def _send(
        self,
        method: str,
        endpoint: str,
        *,
        json_body: dict[str, Any] | None = None,
        query: dict[str, str] | None = None,
    ) -> httpx.Response:
        headers = {"Authorization": f"Bearer {self._api_key}"}
        if json_body is not None:
            headers["Content-Type"] = "application/json"
        if self._http_referer:
            headers["HTTP-Referer"] = self._http_referer
        if self._app_name:
            headers["X-OpenRouter-Title"] = self._app_name
        try:
            async with httpx.AsyncClient(
                timeout=httpx.Timeout(25.0),
                transport=self._transport,
            ) as client:
                return await client.request(
                    method,
                    endpoint,
                    headers=headers,
                    json=json_body,
                    params=query,
                )
        except (httpx.TimeoutException, httpx.NetworkError) as error:
            raise ProviderUnavailableError("OpenRouter request failed") from error
        except httpx.HTTPError as error:
            raise ProviderUnavailableError("OpenRouter request failed") from error

    @staticmethod
    def _raise_for_status(response: httpx.Response) -> None:
        if response.status_code == 429 or response.status_code >= 500:
            raise ProviderUnavailableError("OpenRouter is temporarily unavailable")
        if response.status_code < 200 or response.status_code >= 300:
            raise ProviderRejectedError("OpenRouter rejected the request")

    def _request_payload(self, request: ExtractionRequest) -> dict[str, Any]:
        image_data_url = (
            f"data:{request.mime_type};base64,{request.image_base64}"
        )
        return {
            "model": self.model,
            "messages": [
                {
                    "role": "user",
                    "content": [
                        {"type": "text", "text": _extraction_prompt(request)},
                        {
                            "type": "image_url",
                            "image_url": {"url": image_data_url},
                        },
                    ],
                }
            ],
            "response_format": {
                "type": "json_schema",
                "json_schema": {
                    "name": "snapcal_event_proposal",
                    "strict": True,
                    "schema": _event_response_schema(),
                },
            },
            "provider": {"require_parameters": True},
            "stream": False,
            "temperature": 0,
        }


def _optional_nonnegative_decimal(value: Any) -> Decimal | None:
    if value is None:
        return None
    if isinstance(value, bool) or not isinstance(value, (int, float, Decimal)):
        raise TypeError("cost must be numeric or null")
    decimal_value = Decimal(str(value))
    if not decimal_value.is_finite() or decimal_value < 0:
        raise ValueError("cost must be finite and non-negative")
    return decimal_value


def _extraction_prompt(request: ExtractionRequest) -> str:
    ocr_evidence = "\n".join(
        f"[{index}] confidence={line.confidence:.3f} "
        f"box={line.box.model_dump() if line.box else None} text={line.text}"
        for index, line in enumerate(request.ocr_lines)
    )
    return f"""
You extract one or more calendar events from an image for mandatory human review.
Use the image's visual hierarchy together with the OCR evidence. Logos, sponsors, and organizers are not the event title when a prominent event heading exists.

Safety rules:
- Return a separate event only when it is independently actionable and has its own visible date evidence.
- Preserve the source reading order. Return at most 10 events.
- Do not split schedules, agendas, sponsor lists, or numbered prose unless each item is a distinct calendar event.
- Never invent a date or time. Every proposed date/time must cite visible evidence_text.
- If an event has a date but no clock time, set is_all_day=true and leave both times null. Words such as evening, morning, tối, or sáng are not clock times.
- Date-range end is inclusive from the user's perspective.
- Preserve Vietnamese and English text faithfully.
- A missing or uncertain field must be null and represented by an ambiguity.
- Keep description concise; do not copy sponsor lists unless event-relevant.

Context:
- captured_at: {request.captured_at.isoformat()}
- user_time_zone: {request.time_zone}
- user_locale: {request.locale}

Local OCR evidence in visual reading order:
{ocr_evidence}
""".strip()


def _event_response_schema() -> dict[str, Any]:
    nullable_string = {"anyOf": [{"type": "string"}, {"type": "null"}]}
    evidence_string = {
        "type": "object",
        "properties": {
            "value": nullable_string,
            "evidence_text": nullable_string,
            "confidence": {"type": "number", "minimum": 0, "maximum": 1},
            "is_inferred": {"type": "boolean"},
        },
        "required": ["value", "evidence_text", "confidence", "is_inferred"],
        "additionalProperties": False,
    }
    temporal = {
        "type": "object",
        "properties": {
            "date": nullable_string,
            "time": nullable_string,
            "evidence_text": nullable_string,
            "confidence": {"type": "number", "minimum": 0, "maximum": 1},
            "is_inferred": {"type": "boolean"},
        },
        "required": ["date", "time", "evidence_text", "confidence", "is_inferred"],
        "additionalProperties": False,
    }
    event = {
        "type": "object",
        "properties": {
            "title": evidence_string,
            "start": temporal,
            "end": temporal,
            "location": evidence_string,
            "description": evidence_string,
            "is_all_day": {"type": "boolean"},
            "ambiguities": {
                "type": "array",
                "items": {
                    "type": "object",
                    "properties": {
                        "field": {
                            "type": "string",
                            "enum": ["title", "dateTime", "endTime", "location", "extraction"],
                        },
                        "message": {"type": "string"},
                        "severity": {
                            "type": "string",
                            "enum": ["low", "medium", "high"],
                        },
                    },
                    "required": ["field", "message", "severity"],
                    "additionalProperties": False,
                },
            },
        },
        "required": [
            "title",
            "start",
            "end",
            "location",
            "description",
            "is_all_day",
            "ambiguities",
        ],
        "additionalProperties": False,
    }
    return {
        "type": "object",
        "properties": {
            "events": {
                "type": "array",
                "items": event,
                "minItems": 1,
                "maxItems": 10,
            }
        },
        "required": ["events"],
        "additionalProperties": False,
    }
