from __future__ import annotations

import base64
import binascii
from datetime import date as DateValue
from datetime import datetime
from datetime import time as TimeValue
from typing import Annotated, Literal
from urllib.parse import urlparse

from pydantic import BaseModel, ConfigDict, Field, StringConstraints, model_validator


MAX_IMAGE_BYTES = 20 * 1_024 * 1_024
ContractString = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1)]
OAuthString = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=4_096)]


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


class EventProposalSet(BaseModel):
    model_config = ConfigDict(extra="forbid")

    events: list[EventProposal] = Field(min_length=1, max_length=10)


class ExtractionResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    schema_version: Literal["2"] = "2"
    model: ContractString
    events: list[EventProposal] = Field(min_length=1, max_length=10)


class BenchmarkUsage(BaseModel):
    model_config = ConfigDict(extra="forbid")

    request_cost_usd: float = Field(ge=0, le=5)
    cumulative_cost_usd: float = Field(ge=0, le=5)
    budget_remaining_usd: float = Field(ge=0, le=5)
    request_count: int = Field(ge=0)


class BenchmarkExtractionResponse(ExtractionResponse):
    usage: BenchmarkUsage


class BenchmarkPreflightResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    status: Literal["ok"] = "ok"
    model: ContractString
    budget_ceiling_usd: float = Field(gt=0, le=5)
    provider_key_limit_usd: float = Field(gt=0, le=5)
    provider_key_limit_remaining_usd: float = Field(gt=0, le=5)
    provider_key_limit_reset: str | None = None


class BenchmarkStatusResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    status: Literal["ok"] = "ok"
    model: ContractString
    usage: BenchmarkUsage


class HealthResponse(BaseModel):
    status: Literal["ok"] = "ok"
    provider: Literal["openrouter"] = "openrouter"
    model: str
    ready: bool


class OAuthTokenRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    client_id: Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=300)]
    grant_type: Literal["authorization_code", "refresh_token"]
    code: OAuthString | None = None
    code_verifier: Annotated[
        str,
        StringConstraints(strip_whitespace=True, min_length=43, max_length=128),
    ] | None = None
    redirect_uri: Annotated[
        str,
        StringConstraints(strip_whitespace=True, min_length=1, max_length=500),
    ] | None = None
    refresh_token: OAuthString | None = None

    @model_validator(mode="after")
    def validates_grant(self) -> "OAuthTokenRequest":
        if self.grant_type == "authorization_code":
            if not self.code or not self.code_verifier or not self.redirect_uri:
                raise ValueError("authorization_code requires code, code_verifier, and redirect_uri")
            if self.refresh_token is not None:
                raise ValueError("authorization_code cannot include refresh_token")
            parsed = urlparse(self.redirect_uri)
            if (
                parsed.scheme != "http"
                or parsed.hostname != "127.0.0.1"
                or parsed.port is None
                or parsed.username is not None
                or parsed.password is not None
                or parsed.query
                or parsed.fragment
                or parsed.path not in ("", "/")
            ):
                raise ValueError("redirect_uri must be a loopback IPv4 callback")
        else:
            if not self.refresh_token:
                raise ValueError("refresh_token grant requires refresh_token")
            if self.code is not None or self.code_verifier is not None or self.redirect_uri is not None:
                raise ValueError("refresh_token grant cannot include authorization-code fields")
        return self


class OAuthTokenResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    access_token: OAuthString
    expires_in: float = Field(gt=0, le=86_400)
    refresh_token: OAuthString | None = None
