from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from typing import Protocol

import httpx
from pydantic import BaseModel, Field, ValidationError

from .contracts import OAuthTokenRequest, OAuthTokenResponse


GOOGLE_TOKEN_ENDPOINT = "https://oauth2.googleapis.com/token"


class OAuthBrokerUnavailableError(RuntimeError):
    pass


class OAuthClientMismatchError(RuntimeError):
    pass


class OAuthProviderRejectedError(RuntimeError):
    pass


class OAuthTokenBroker(Protocol):
    async def exchange(self, request: OAuthTokenRequest) -> OAuthTokenResponse: ...


@dataclass(frozen=True)
class UnavailableOAuthTokenBroker:
    async def exchange(self, request: OAuthTokenRequest) -> OAuthTokenResponse:
        raise OAuthBrokerUnavailableError("Google OAuth credentials are not configured")


class _InstalledCredentials(BaseModel):
    client_id: str = Field(min_length=1, max_length=300)
    client_secret: str = Field(min_length=1, max_length=4_096)


class _CredentialFile(BaseModel):
    installed: _InstalledCredentials


class _ProviderTokenResponse(BaseModel):
    access_token: str = Field(min_length=1, max_length=4_096)
    expires_in: float = Field(gt=0, le=86_400)
    refresh_token: str | None = Field(default=None, min_length=1, max_length=4_096)


class GoogleOAuthTokenBroker:
    def __init__(
        self,
        credential_file: Path,
        transport: httpx.AsyncBaseTransport | None = None,
    ) -> None:
        try:
            with credential_file.expanduser().open(encoding="utf-8") as handle:
                payload = json.load(handle)
            credentials = _CredentialFile.model_validate(payload).installed
        except (OSError, json.JSONDecodeError, ValidationError) as error:
            raise OAuthBrokerUnavailableError("Google OAuth credential file is unavailable") from error

        self._client_id = credentials.client_id
        self._client_secret = credentials.client_secret
        self._transport = transport

    async def exchange(self, request: OAuthTokenRequest) -> OAuthTokenResponse:
        if request.client_id != self._client_id:
            raise OAuthClientMismatchError("OAuth client ID does not match configured credentials")

        form = {
            "client_id": self._client_id,
            "client_secret": self._client_secret,
            "grant_type": request.grant_type,
        }
        if request.grant_type == "authorization_code":
            form.update(
                {
                    "code": request.code or "",
                    "code_verifier": request.code_verifier or "",
                    "redirect_uri": request.redirect_uri or "",
                }
            )
        else:
            form["refresh_token"] = request.refresh_token or ""

        try:
            async with httpx.AsyncClient(
                timeout=httpx.Timeout(15.0),
                transport=self._transport,
            ) as client:
                response = await client.post(GOOGLE_TOKEN_ENDPOINT, data=form)
        except (httpx.TimeoutException, httpx.NetworkError, httpx.HTTPError) as error:
            raise OAuthBrokerUnavailableError("Google token exchange is unavailable") from error

        if response.status_code < 200 or response.status_code >= 300:
            raise OAuthProviderRejectedError("Google rejected the OAuth token exchange")

        try:
            provider = _ProviderTokenResponse.model_validate(response.json())
        except (ValueError, ValidationError) as error:
            raise OAuthProviderRejectedError("Google returned an invalid token response") from error

        return OAuthTokenResponse(
            access_token=provider.access_token,
            expires_in=provider.expires_in,
            refresh_token=provider.refresh_token,
        )
