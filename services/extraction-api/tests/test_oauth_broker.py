from __future__ import annotations

import asyncio
import json
from pathlib import Path
from urllib.parse import parse_qs

import httpx
import pytest

from app.contracts import OAuthTokenRequest
from app.oauth_broker import (
    GoogleOAuthTokenBroker,
    OAuthClientMismatchError,
    OAuthProviderRejectedError,
)


def credential_file(path: Path) -> Path:
    path.write_text(
        json.dumps(
            {
                "installed": {
                    "client_id": "desktop-client-id",
                    "client_secret": "private-client-secret",
                }
            }
        ),
        encoding="utf-8",
    )
    return path


def authorization_request() -> OAuthTokenRequest:
    return OAuthTokenRequest.model_validate(
        {
            "client_id": "desktop-client-id",
            "grant_type": "authorization_code",
            "code": "private-authorization-code",
            "code_verifier": "v" * 43,
            "redirect_uri": "http://127.0.0.1:49152",
        }
    )


def test_broker_adds_secret_only_to_google_request(tmp_path: Path) -> None:
    captured: dict[str, str] = {}

    def handler(request: httpx.Request) -> httpx.Response:
        captured["url"] = str(request.url)
        captured["body"] = request.content.decode("utf-8")
        return httpx.Response(
            200,
            json={
                "access_token": "google-access-token",
                "expires_in": 3_600,
                "refresh_token": "google-refresh-token",
                "scope": "ignored-provider-field",
                "token_type": "Bearer",
            },
        )

    broker = GoogleOAuthTokenBroker(
        credential_file(tmp_path / "oauth.json"),
        transport=httpx.MockTransport(handler),
    )
    result = asyncio.run(broker.exchange(authorization_request()))

    form = parse_qs(captured["body"])
    assert captured["url"] == "https://oauth2.googleapis.com/token"
    assert form["client_id"] == ["desktop-client-id"]
    assert form["client_secret"] == ["private-client-secret"]
    assert form["code"] == ["private-authorization-code"]
    assert form["code_verifier"] == ["v" * 43]
    assert result.model_dump() == {
        "access_token": "google-access-token",
        "expires_in": 3_600.0,
        "refresh_token": "google-refresh-token",
    }
    assert "private-client-secret" not in result.model_dump_json()


def test_broker_rejects_mismatched_client_before_provider_call(tmp_path: Path) -> None:
    calls = 0

    def handler(_: httpx.Request) -> httpx.Response:
        nonlocal calls
        calls += 1
        return httpx.Response(200, json={})

    broker = GoogleOAuthTokenBroker(
        credential_file(tmp_path / "oauth.json"),
        transport=httpx.MockTransport(handler),
    )
    request = authorization_request().model_copy(update={"client_id": "other-client"})

    with pytest.raises(OAuthClientMismatchError):
        asyncio.run(broker.exchange(request))
    assert calls == 0


def test_broker_redacts_google_error_body(tmp_path: Path) -> None:
    broker = GoogleOAuthTokenBroker(
        credential_file(tmp_path / "oauth.json"),
        transport=httpx.MockTransport(
            lambda _: httpx.Response(
                400,
                json={"error": "invalid_grant", "error_description": "private provider detail"},
            )
        ),
    )

    with pytest.raises(OAuthProviderRejectedError) as caught:
        asyncio.run(broker.exchange(authorization_request()))
    assert "private provider detail" not in str(caught.value)
    assert "private-client-secret" not in str(caught.value)
