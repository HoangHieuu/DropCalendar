from __future__ import annotations

import asyncio
import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Protocol

import httpx
from google.auth.transport.requests import Request as GoogleAuthRequest
from google.oauth2 import id_token as google_id_token
from pydantic import BaseModel, Field, ValidationError

from .contracts_v2 import GoogleExchangeRequest


GOOGLE_TOKEN_ENDPOINT = "https://oauth2.googleapis.com/token"


class IdentityUnavailableError(RuntimeError):
    pass


class IdentityRejectedError(RuntimeError):
    pass


@dataclass(frozen=True)
class GoogleIdentityResult:
    subject: str
    email: str
    access_token: str
    expires_in: float
    refresh_token: str | None


class GoogleIdentityExchanging(Protocol):
    async def exchange(self, request: GoogleExchangeRequest) -> GoogleIdentityResult: ...


@dataclass(frozen=True)
class UnavailableGoogleIdentityBroker:
    async def exchange(self, request: GoogleExchangeRequest) -> GoogleIdentityResult:
        raise IdentityUnavailableError("Google identity is not configured")


class _InstalledCredentials(BaseModel):
    client_id: str = Field(min_length=1, max_length=300)
    client_secret: str = Field(min_length=1, max_length=4096)


class _CredentialFile(BaseModel):
    installed: _InstalledCredentials


class _GoogleTokenResponse(BaseModel):
    access_token: str = Field(min_length=1, max_length=4096)
    expires_in: float = Field(gt=0, le=86_400)
    refresh_token: str | None = Field(default=None, min_length=1, max_length=4096)
    id_token: str = Field(min_length=1, max_length=16_384)


class GoogleIdentityBroker:
    def __init__(
        self,
        credential_file: Path,
        client: httpx.AsyncClient | None = None,
    ) -> None:
        try:
            with credential_file.expanduser().open(encoding="utf-8") as handle:
                credentials = _CredentialFile.model_validate(json.load(handle)).installed
        except (OSError, json.JSONDecodeError, ValidationError) as error:
            raise IdentityUnavailableError("Google OAuth credentials are unavailable") from error
        self._client_id = credentials.client_id
        self._client_secret = credentials.client_secret
        self._client = client or httpx.AsyncClient(
            timeout=httpx.Timeout(15.0),
            limits=httpx.Limits(max_connections=10, max_keepalive_connections=5),
        )
        self._owns_client = client is None

    async def close(self) -> None:
        if self._owns_client:
            await self._client.aclose()

    async def exchange(self, request: GoogleExchangeRequest) -> GoogleIdentityResult:
        try:
            response = await self._client.post(
                GOOGLE_TOKEN_ENDPOINT,
                data={
                    "client_id": self._client_id,
                    "client_secret": self._client_secret,
                    "grant_type": "authorization_code",
                    "code": request.authorization_code,
                    "code_verifier": request.pkce_verifier,
                    "redirect_uri": request.redirect_uri,
                },
            )
        except (httpx.TimeoutException, httpx.NetworkError, httpx.HTTPError) as error:
            raise IdentityUnavailableError("Google identity exchange is unavailable") from error
        if response.status_code < 200 or response.status_code >= 300:
            raise IdentityRejectedError("Google rejected the identity exchange")
        try:
            provider = _GoogleTokenResponse.model_validate(response.json())
            claims = await asyncio.to_thread(
                google_id_token.verify_oauth2_token,
                provider.id_token,
                GoogleAuthRequest(),
                self._client_id,
            )
            _validate_claims(claims, request.nonce)
        except (ValueError, ValidationError, KeyError, TypeError) as error:
            raise IdentityRejectedError("Google identity token is invalid") from error
        return GoogleIdentityResult(
            subject=claims["sub"],
            email=claims["email"].strip().lower(),
            access_token=provider.access_token,
            expires_in=provider.expires_in,
            refresh_token=provider.refresh_token,
        )


def _validate_claims(claims: dict[str, Any], nonce: str) -> None:
    if claims.get("nonce") != nonce:
        raise ValueError("nonce mismatch")
    subject = claims.get("sub")
    email = claims.get("email")
    if not isinstance(subject, str) or not subject.strip():
        raise ValueError("subject missing")
    if not isinstance(email, str) or not email.strip() or claims.get("email_verified") is not True:
        raise ValueError("verified email missing")
