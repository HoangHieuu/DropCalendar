from __future__ import annotations

import base64
import binascii
from datetime import date as DateValue
from datetime import datetime
from datetime import time as TimeValue
from typing import Annotated, Literal

from pydantic import BaseModel, ConfigDict, Field, StringConstraints, model_validator


MAX_IMAGE_BYTES = 20 * 1_024 * 1_024
ContractString = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1)]


class OCRBox(BaseModel):
    model_config = ConfigDict(extra="forbid")

    x: float = Field(ge=0, le=1)
    y: float = Field(ge=0, le=1)
    width: float = Field(gt=0, le=1)
    height: float = Field(gt=0, le=1)

    @model_validator(mode="after")
    def stays_inside_image(self) -> "OCRBox":
        if self.x + self.width > 1.001 or self.y + self.height > 1.001:
            raise ValueError("OCR box must stay inside normalized image bounds")
        return self


class OCRLine(BaseModel):
    model_config = ConfigDict(extra="forbid")

    text: Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=500)]
    confidence: float = Field(ge=0, le=1)
    box: OCRBox | None = None


class ExtractionRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    schema_version: Literal["1"]
    image_base64: Annotated[str, StringConstraints(min_length=4, max_length=28_000_000)]
    mime_type: Literal["image/jpeg", "image/png"]
    captured_at: datetime
    time_zone: Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=100)]
    locale: Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=50)]
    ocr_lines: list[OCRLine] = Field(min_length=1, max_length=500)

    def decoded_image(self) -> bytes:
        try:
            decoded = base64.b64decode(self.image_base64, validate=True)
        except (binascii.Error, ValueError) as error:
            raise ValueError("image_base64 must be valid base64") from error
        if not decoded or len(decoded) > MAX_IMAGE_BYTES:
            raise ValueError("decoded image must contain 1 byte to 20 MB")
        if self.mime_type == "image/jpeg" and not decoded.startswith(b"\xff\xd8\xff"):
            raise ValueError("image content does not match image/jpeg")
        if self.mime_type == "image/png" and not decoded.startswith(b"\x89PNG\r\n\x1a\n"):
            raise ValueError("image content does not match image/png")
        return decoded

    @model_validator(mode="after")
    def validates_image(self) -> "ExtractionRequest":
        self.decoded_image()
        return self


class EvidenceString(BaseModel):
    model_config = ConfigDict(extra="forbid")

    value: str | None = None
    evidence_text: str | None = None
    confidence: float = Field(ge=0, le=1)
    is_inferred: bool = False

    @model_validator(mode="after")
    def evidence_for_value(self) -> "EvidenceString":
        if self.value is not None and not self.value.strip():
            raise ValueError("value cannot be blank")
        if self.evidence_text is not None and not self.evidence_text.strip():
            raise ValueError("evidence_text cannot be blank")
        return self


class EvidenceTemporal(BaseModel):
    model_config = ConfigDict(extra="forbid")

    date: DateValue | None = None
    time: TimeValue | None = None
    evidence_text: str | None = None
    confidence: float = Field(ge=0, le=1)
    is_inferred: bool = False

    @model_validator(mode="after")
    def evidence_for_date(self) -> "EvidenceTemporal":
        if self.date is not None and not (self.evidence_text or "").strip():
            raise ValueError("a proposed date requires evidence_text")
        if self.time is not None and self.date is None:
            raise ValueError("a proposed time requires a date")
        return self


class ProviderAmbiguity(BaseModel):
    model_config = ConfigDict(extra="forbid")

    field: Literal["title", "dateTime", "endTime", "location", "extraction"]
    message: ContractString
    severity: Literal["low", "medium", "high"]


class EventProposal(BaseModel):
    model_config = ConfigDict(extra="forbid")

    title: EvidenceString
    start: EvidenceTemporal
    end: EvidenceTemporal
    location: EvidenceString
    description: EvidenceString
    is_all_day: bool
    ambiguities: list[ProviderAmbiguity] = Field(default_factory=list, max_length=20)

    @model_validator(mode="after")
    def temporal_contract(self) -> "EventProposal":
        if self.start.date is None:
            raise ValueError("event proposal requires a start date")
        if self.is_all_day:
            if self.start.time is not None or self.end.time is not None:
                raise ValueError("all-day proposals cannot contain times")
        elif self.start.time is None:
            raise ValueError("timed proposals require a start time")

        if self.end.date is not None:
            start_value = datetime.combine(self.start.date, self.start.time or TimeValue.min)
            end_value = datetime.combine(self.end.date, self.end.time or TimeValue.max)
            if end_value < start_value:
                raise ValueError("event end cannot precede start")
        return self


class ExtractionResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    schema_version: Literal["1"] = "1"
    model: ContractString
    event: EventProposal


class HealthResponse(BaseModel):
    status: Literal["ok"] = "ok"
    provider: Literal["gemini"] = "gemini"
    model: str
    ready: bool
