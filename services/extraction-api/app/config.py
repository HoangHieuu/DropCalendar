from __future__ import annotations

import base64
import os
from dataclasses import dataclass
from decimal import Decimal, InvalidOperation
from urllib.parse import urlparse


class ConfigurationError(RuntimeError):
    pass


@dataclass(frozen=True)
class ProductionSettings:
    environment: str
    database_url: str
    session_signing_key: bytes
    input_hmac_key: bytes
    api_base_url: str
    web_base_url: str
    paddle_environment: str
    paddle_api_key: str
    paddle_webhook_secret: str
    paddle_price_id: str
    provider_monthly_budget_usd: Decimal
    result_ttl_seconds: int = 900
    access_token_ttl_seconds: int = 900
    refresh_token_ttl_days: int = 30
    database_pool_size: int = 4
    cloud_tasks_project: str | None = None
    cloud_tasks_location: str | None = None
    cloud_tasks_queue: str | None = None
    cloud_tasks_service_account: str | None = None

    @classmethod
    def from_environment(cls) -> "ProductionSettings | None":
        enabled = os.environ.get("SNAPCAL_PRODUCTION_MODE", "0").strip()
        if enabled not in {"0", "1"}:
            raise ConfigurationError("SNAPCAL_PRODUCTION_MODE must be 0 or 1")
        if enabled == "0":
            return None

        environment = _required("SNAPCAL_ENVIRONMENT")
        if environment not in {"staging", "production", "test"}:
            raise ConfigurationError(
                "SNAPCAL_ENVIRONMENT must be staging, production, or test"
            )
        database_url = _required("DATABASE_URL")
        if not database_url.startswith(
            ("postgresql+asyncpg://", "sqlite+aiosqlite://")
        ):
            raise ConfigurationError("DATABASE_URL must use an async SQLAlchemy driver")
        if environment != "test" and not database_url.startswith("postgresql+asyncpg://"):
            raise ConfigurationError("staging and production require PostgreSQL")

        api_base_url = _https_url("SNAPCAL_API_BASE_URL")
        web_base_url = _https_url("SNAPCAL_WEB_BASE_URL")
        paddle_environment = os.environ.get("PADDLE_ENVIRONMENT", "sandbox").strip()
        if paddle_environment not in {"sandbox", "production"}:
            raise ConfigurationError("PADDLE_ENVIRONMENT must be sandbox or production")
        if environment == "production" and paddle_environment != "production":
            raise ConfigurationError("production must use the Paddle production environment")

        try:
            provider_budget = Decimal(
                os.environ.get("SNAPCAL_PROVIDER_MONTHLY_BUDGET_USD", "25")
            )
        except InvalidOperation as error:
            raise ConfigurationError("provider budget must be a decimal") from error
        if not provider_budget.is_finite() or provider_budget <= 0 or provider_budget > 25:
            raise ConfigurationError("provider budget must be greater than 0 and at most 25")

        cloud_tasks_project = None
        cloud_tasks_location = None
        cloud_tasks_queue = None
        cloud_tasks_service_account = None
        if environment != "test":
            cloud_tasks_project = _required("GOOGLE_CLOUD_PROJECT")
            cloud_tasks_location = os.environ.get(
                "SNAPCAL_TASKS_LOCATION", "asia-southeast1"
            ).strip()
            if cloud_tasks_location != "asia-southeast1":
                raise ConfigurationError(
                    "SNAPCAL_TASKS_LOCATION must be asia-southeast1"
                )
            cloud_tasks_queue = _required("SNAPCAL_TASKS_QUEUE")
            cloud_tasks_service_account = _required(
                "SNAPCAL_TASKS_SERVICE_ACCOUNT"
            )
            if not cloud_tasks_service_account.endswith(".iam.gserviceaccount.com"):
                raise ConfigurationError(
                    "SNAPCAL_TASKS_SERVICE_ACCOUNT must be a service-account email"
                )

        return cls(
            environment=environment,
            database_url=database_url,
            session_signing_key=_secret("SNAPCAL_SESSION_SIGNING_KEY"),
            input_hmac_key=_secret("SNAPCAL_INPUT_HMAC_KEY"),
            api_base_url=api_base_url,
            web_base_url=web_base_url,
            paddle_environment=paddle_environment,
            paddle_api_key=_required("PADDLE_API_KEY"),
            paddle_webhook_secret=_required("PADDLE_WEBHOOK_SECRET"),
            paddle_price_id=_required("PADDLE_PRICE_ID"),
            provider_monthly_budget_usd=provider_budget,
            cloud_tasks_project=cloud_tasks_project,
            cloud_tasks_location=cloud_tasks_location,
            cloud_tasks_queue=cloud_tasks_queue,
            cloud_tasks_service_account=cloud_tasks_service_account,
        )


def _required(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        raise ConfigurationError(f"{name} is required")
    return value


def _secret(name: str) -> bytes:
    value = _required(name)
    try:
        decoded = base64.urlsafe_b64decode(value + "=" * (-len(value) % 4))
    except ValueError as error:
        raise ConfigurationError(f"{name} must be URL-safe base64") from error
    if len(decoded) < 32:
        raise ConfigurationError(f"{name} must decode to at least 32 bytes")
    return decoded


def _https_url(name: str) -> str:
    value = _required(name).rstrip("/")
    parsed = urlparse(value)
    if parsed.scheme != "https" or not parsed.netloc or parsed.query or parsed.fragment:
        raise ConfigurationError(f"{name} must be an HTTPS origin")
    return value
