from __future__ import annotations

import asyncio
import json
from dataclasses import dataclass
from typing import Any, Protocol

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
class UnavailableGeminiProvider:
    model: str

    @property
    def ready(self) -> bool:
        return False

    async def extract(self, request: ExtractionRequest) -> EventProposal:
        raise ProviderUnavailableError("Gemini authorization is not configured")


class GeminiProvider:
    def __init__(self, api_key: str, model: str) -> None:
        try:
            from google import genai
        except ImportError as error:
            raise ProviderUnavailableError(
                "google-genai is not installed; install services/extraction-api/requirements.txt"
            ) from error

        self.model = model
        self._client = genai.Client(api_key=api_key)

    @property
    def ready(self) -> bool:
        return True

    async def extract(self, request: ExtractionRequest) -> EventProposal:
        try:
            interaction = await asyncio.wait_for(
                asyncio.to_thread(self._create_interaction, request),
                timeout=25,
            )
        except TimeoutError as error:
            raise ProviderUnavailableError("Gemini extraction timed out") from error
        except ProviderUnavailableError:
            raise
        except Exception as error:
            raise ProviderRejectedError("Gemini request failed") from error

        output_text = getattr(interaction, "output_text", None)
        if not isinstance(output_text, str) or not output_text.strip():
            raise InvalidProviderOutputError("Gemini returned no structured text")
        try:
            payload = json.loads(output_text)
            return EventProposal.model_validate(payload)
        except (json.JSONDecodeError, ValueError) as error:
            raise InvalidProviderOutputError("Gemini output failed contract validation") from error

    def _create_interaction(self, request: ExtractionRequest) -> Any:
        ocr_evidence = "\n".join(
            f"[{index}] confidence={line.confidence:.3f} box={line.box.model_dump() if line.box else None} text={line.text}"
            for index, line in enumerate(request.ocr_lines)
        )
        prompt = f"""
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

        return self._client.interactions.create(
            model=self.model,
            store=False,
            input=[
                {"type": "text", "text": prompt},
                {
                    "type": "image",
                    "data": request.image_base64,
                    "mime_type": request.mime_type,
                },
            ],
            response_format={
                "type": "text",
                "mime_type": "application/json",
                "schema": _gemini_response_schema(),
            },
        )


def _gemini_response_schema() -> dict[str, Any]:
    evidence_string = {
        "type": "object",
        "properties": {
            "value": {"type": ["string", "null"]},
            "evidence_text": {"type": ["string", "null"]},
            "confidence": {"type": "number", "minimum": 0, "maximum": 1},
            "is_inferred": {"type": "boolean"},
        },
        "required": ["value", "evidence_text", "confidence", "is_inferred"],
        "additionalProperties": False,
    }
    temporal = {
        "type": "object",
        "properties": {
            "date": {"type": ["string", "null"], "format": "date"},
            "time": {"type": ["string", "null"]},
            "evidence_text": {"type": ["string", "null"]},
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
                        "severity": {"type": "string", "enum": ["low", "medium", "high"]},
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
