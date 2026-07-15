from __future__ import annotations

import hashlib
import hmac
import secrets
import uuid
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from typing import Any

import jwt


class InvalidAccessTokenError(RuntimeError):
    pass


@dataclass(frozen=True)
class AccessClaims:
    user_id: uuid.UUID
    session_id: uuid.UUID
    device_id: str


class SessionTokenCodec:
    issuer = "snapcal"
    audience = "snapcal-api"

    def __init__(self, signing_key: bytes, access_ttl_seconds: int = 900) -> None:
        self._key = signing_key
        self._access_ttl_seconds = access_ttl_seconds

    def access_token(
        self, *, user_id: uuid.UUID, session_id: uuid.UUID, device_id: str
    ) -> tuple[str, datetime]:
        now = datetime.now(UTC)
        expires_at = now + timedelta(seconds=self._access_ttl_seconds)
        payload: dict[str, Any] = {
            "iss": self.issuer,
            "aud": self.audience,
            "sub": str(user_id),
            "sid": str(session_id),
            "device": device_id,
            "iat": now,
            "exp": expires_at,
            "jti": secrets.token_urlsafe(16),
        }
        return jwt.encode(payload, self._key, algorithm="HS256"), expires_at

    def decode(self, token: str) -> AccessClaims:
        try:
            payload = jwt.decode(
                token,
                self._key,
                algorithms=["HS256"],
                audience=self.audience,
                issuer=self.issuer,
                options={"require": ["sub", "sid", "device", "iat", "exp", "jti"]},
            )
            device_id = payload["device"]
            if not isinstance(device_id, str) or not device_id:
                raise ValueError("invalid device")
            return AccessClaims(
                user_id=uuid.UUID(payload["sub"]),
                session_id=uuid.UUID(payload["sid"]),
                device_id=device_id,
            )
        except (jwt.PyJWTError, KeyError, TypeError, ValueError) as error:
            raise InvalidAccessTokenError("access token is invalid") from error

    @staticmethod
    def refresh_token(session_id: uuid.UUID) -> str:
        return f"{session_id}.{secrets.token_urlsafe(48)}"

    @staticmethod
    def refresh_session_id(token: str) -> uuid.UUID:
        try:
            identifier, secret = token.split(".", 1)
            if len(secret) < 40:
                raise ValueError("short token")
            return uuid.UUID(identifier)
        except (ValueError, AttributeError) as error:
            raise InvalidAccessTokenError("refresh token is invalid") from error


def secret_hash(value: str, key: bytes) -> str:
    return hmac.new(key, value.encode("utf-8"), hashlib.sha256).hexdigest()


def input_hmac(*, user_id: uuid.UUID, image: bytes, key: bytes) -> str:
    image_digest = hashlib.sha256(image).digest()
    return hmac.new(key, user_id.bytes + image_digest, hashlib.sha256).hexdigest()


def constant_time_equal(left: str | None, right: str) -> bool:
    return left is not None and hmac.compare_digest(left, right)

