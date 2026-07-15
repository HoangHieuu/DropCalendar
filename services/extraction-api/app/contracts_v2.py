from __future__ import annotations

import base64
import binascii
from datetime import datetime
from typing import Annotated, Literal

from pydantic import BaseModel, ConfigDict, Field, StringConstraints, field_validator

from .contracts import EventProposal, OCRLine


MAX_V2_IMAGE_BYTES = 4 * 1_024 * 1_024


class ErrorBody(BaseModel):
    code: str
    message: str
    retryable: bool
    request_id: str


class ErrorEnvelope(BaseModel):
    error: ErrorBody


class GoogleExchangeRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    authorization_code: Annotated[str, StringConstraints(min_length=1, max_length=4096)]
    pkce_verifier: Annotated[str, StringConstraints(min_length=43, max_length=128)]
    redirect_uri: Annotated[str, StringConstraints(min_length=1, max_length=500)]
    nonce: Annotated[str, StringConstraints(min_length=16, max_length=256)]
    device_id: Annotated[str, StringConstraints(min_length=8, max_length=255)]

    @field_validator("redirect_uri")
    @classmethod
    def loopback_redirect(cls, value: str) -> str:
        from urllib.parse import urlparse

        parsed = urlparse(value)
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
            raise ValueError("redirect_uri must be an IPv4 loopback callback")
        return value


class SessionRefreshRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    refresh_token: Annotated[str, StringConstraints(min_length=40, max_length=512)]


class SessionTokens(BaseModel):
    access_token: str
    access_token_expires_at: datetime
    refresh_token: str
    refresh_token_expires_at: datetime


class GoogleTransientTokens(BaseModel):
    access_token: str
    expires_in: float
    refresh_token: str | None = None


class GoogleExchangeResponse(BaseModel):
    user_id: str
    email: str
    invited: bool
    session: SessionTokens
    google: GoogleTransientTokens


class PlanResponse(BaseModel):
    code: str
    display_name: str
    price_usd_cents: int
    monthly_quota: int
    per_minute_limit: int
    per_day_limit: int
    concurrent_limit: int
    accuracy_enabled: bool


class QuotaSnapshot(BaseModel):
    limit: int
    used: int
    reserved: int
    remaining: int
    period_end: datetime | None


class MeResponse(BaseModel):
    user_id: str
    email: str
    invited: bool
    subscription_status: str
    plan: PlanResponse
    quota: QuotaSnapshot
    payment_warning: bool


class HostedURLResponse(BaseModel):
    url: str


class V2ExtractionMetadata(BaseModel):
    model_config = ConfigDict(extra="forbid")

    schema_version: Literal["2"] = "2"
    captured_at: datetime
    time_zone: Annotated[str, StringConstraints(min_length=1, max_length=100)]
    locale: Annotated[str, StringConstraints(min_length=1, max_length=50)]
    ocr_lines: list[OCRLine] = Field(min_length=1, max_length=150)
    retry_public_key: Annotated[str, StringConstraints(min_length=40, max_length=64)]

    @field_validator("retry_public_key")
    @classmethod
    def valid_curve25519_key(cls, value: str) -> str:
        try:
            raw = base64.urlsafe_b64decode(value + "=" * (-len(value) % 4))
        except (binascii.Error, ValueError) as error:
            raise ValueError("retry_public_key must be URL-safe base64") from error
        if len(raw) != 32:
            raise ValueError("retry_public_key must contain 32 bytes")
        return value

    @field_validator("ocr_lines")
    @classmethod
    def bounded_ocr(cls, lines: list[OCRLine]) -> list[OCRLine]:
        if sum(len(line.text) for line in lines) > 20_000:
            raise ValueError("OCR text exceeds 20,000 characters")
        return lines


class V2ExtractionResponse(BaseModel):
    schema_version: Literal["2"] = "2"
    request_id: str
    model: str
    events: list[EventProposal] = Field(min_length=1, max_length=10)
    quota: QuotaSnapshot


class RetryEnvelopeResponse(BaseModel):
    request_id: str
    algorithm: Literal["x25519-hkdf-sha256-chachapoly"] = (
        "x25519-hkdf-sha256-chachapoly"
    )
    envelope_base64: str
    expires_at: datetime


class WebhookAcceptedResponse(BaseModel):
    accepted: bool = True
    duplicate: bool = False
