from __future__ import annotations

import json
from dataclasses import dataclass
from typing import Any, Protocol
from urllib.parse import urlparse

import httpx

from .contracts import EventProposal, ExtractionRequest


class ProviderUnavailableError(RuntimeError):
    pass


class ProviderRejectedError(RuntimeError):
    pass


class InvalidProviderOutputError(RuntimeError):
    pass


class ExtractionProvider(Protocol):
    model: str

    @property
    def ready(self) -> bool: ...

    async def extract(self, request: ExtractionRequest) -> EventProposal: ...


@dataclass(frozen=True)
class UnavailableOpenRouterProvider:
    model: str

    @property
    def ready(self) -> bool:
        return False

    async def extract(self, request: ExtractionRequest) -> EventProposal:
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
        endpoint = f"{base_url.rstrip('/')}/chat/completions"
        parsed = urlparse(endpoint)
        if not key or not selected_model:
            raise ProviderUnavailableError("OpenRouter configuration is incomplete")
        if parsed.scheme != "https" or not parsed.netloc:
            raise ProviderUnavailableError("OpenRouter endpoint must use HTTPS")

        self.model = selected_model
        self._api_key = key
        self._endpoint = endpoint
        self._http_referer = (http_referer or "").strip()
        self._app_name = (app_name or "").strip()
        self._transport = transport

    @property
    def ready(self) -> bool:
        return True

    async def extract(self, request: ExtractionRequest) -> EventProposal:
        headers = {
            "Authorization": f"Bearer {self._api_key}",
            "Content-Type": "application/json",
        }
        if self._http_referer:
            headers["HTTP-Referer"] = self._http_referer
        if self._app_name:
            headers["X-OpenRouter-Title"] = self._app_name

        try:
            async with httpx.AsyncClient(
                timeout=httpx.Timeout(25.0),
                transport=self._transport,
            ) as client:
                response = await client.post(
                    self._endpoint,
                    headers=headers,
                    json=self._request_payload(request),
                )
        except (httpx.TimeoutException, httpx.NetworkError) as error:
            raise ProviderUnavailableError("OpenRouter request failed") from error
        except httpx.HTTPError as error:
            raise ProviderUnavailableError("OpenRouter request failed") from error

        if response.status_code == 429 or response.status_code >= 500:
            raise ProviderUnavailableError("OpenRouter is temporarily unavailable")
        if response.status_code < 200 or response.status_code >= 300:
            raise ProviderRejectedError("OpenRouter rejected the request")

        try:
            envelope = response.json()
            output_text = envelope["choices"][0]["message"]["content"]
            if not isinstance(output_text, str) or not output_text.strip():
                raise ValueError("missing structured content")
            payload = json.loads(output_text)
            return EventProposal.model_validate(payload)
        except (json.JSONDecodeError, KeyError, IndexError, TypeError, ValueError) as error:
            raise InvalidProviderOutputError(
                "OpenRouter output failed contract validation"
            ) from error

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


def _extraction_prompt(request: ExtractionRequest) -> str:
    ocr_evidence = "\n".join(
        f"[{index}] confidence={line.confidence:.3f} "
        f"box={line.box.model_dump() if line.box else None} text={line.text}"
        for index, line in enumerate(request.ocr_lines)
    )
    return f"""
You extract exactly one calendar event from an event poster for mandatory human review.
Use the image's visual hierarchy together with the OCR evidence. Logos, sponsors, and organizers are not the event title when a prominent event heading exists.

Safety rules:
- Never invent a date or time. Every proposed date/time must cite visible evidence_text.
- If a poster has dates but no clock time, set is_all_day=true and leave both times null.
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
    return {
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
