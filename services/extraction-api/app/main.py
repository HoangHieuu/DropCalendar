from __future__ import annotations

import os
from pathlib import Path
from typing import Any

from fastapi import FastAPI, HTTPException
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from dotenv import load_dotenv

from .benchmark import (
    BenchmarkBudget,
    BenchmarkBudgetExceededError,
    BenchmarkConfigurationError,
    BenchmarkPreflightError,
    BenchmarkUsageSnapshot,
)
from .contracts import (
    BenchmarkExtractionResponse,
    BenchmarkPreflightResponse,
    BenchmarkStatusResponse,
    BenchmarkUsage,
    ExtractionRequest,
    ExtractionResponse,
    HealthResponse,
    OAuthTokenRequest,
    OAuthTokenResponse,
)
from .oauth_broker import (
    GoogleOAuthTokenBroker,
    OAuthBrokerUnavailableError,
    OAuthClientMismatchError,
    OAuthProviderRejectedError,
    OAuthTokenBroker,
    UnavailableOAuthTokenBroker,
)
from .provider import (
    BenchmarkExtractionProvider,
    ExtractionProvider,
    InvalidProviderOutputError,
    OpenRouterProvider,
    ProviderRejectedError,
    ProviderUnavailableError,
    ProviderUsageUnavailableError,
    UnavailableOpenRouterProvider,
)


ROOT_DIRECTORY = Path(__file__).resolve().parents[3]
load_dotenv(ROOT_DIRECTORY / ".env", override=False)

DEFAULT_MODEL = "google/gemini-3.1-flash-lite"
DEFAULT_BASE_URL = "https://openrouter.ai/api/v1"


def configured_provider() -> ExtractionProvider:
    model = os.environ.get("OPENROUTER_MODEL", DEFAULT_MODEL).strip() or DEFAULT_MODEL
    api_key = os.environ.get("OPENROUTER_API_KEY", "").strip()
    if not api_key:
        return UnavailableOpenRouterProvider(model=model)
    try:
        return OpenRouterProvider(
            api_key=api_key,
            model=model,
            base_url=os.environ.get("OPENROUTER_BASE_URL", DEFAULT_BASE_URL),
            http_referer=os.environ.get("OPENROUTER_HTTP_REFERER"),
            app_name=os.environ.get("OPENROUTER_APP_NAME", "SnapCal"),
        )
    except ProviderUnavailableError:
        return UnavailableOpenRouterProvider(model=model)


def configured_oauth_broker() -> OAuthTokenBroker:
    credential_path = os.environ.get("GOOGLE_OAUTH_CREDENTIALS_FILE", "").strip()
    if not credential_path:
        return UnavailableOAuthTokenBroker()
    try:
        return GoogleOAuthTokenBroker(Path(credential_path))
    except OAuthBrokerUnavailableError:
        return UnavailableOAuthTokenBroker()


def configured_benchmark_budget() -> BenchmarkBudget | None:
    mode = os.environ.get("SNAPCAL_BENCHMARK_MODE", "0").strip()
    if mode not in {"0", "1"}:
        raise BenchmarkConfigurationError("SNAPCAL_BENCHMARK_MODE must be 0 or 1")
    if mode != "1":
        return None
    ceiling = os.environ.get("SNAPCAL_BENCHMARK_BUDGET_USD", "").strip()
    if not ceiling:
        raise BenchmarkConfigurationError(
            "SNAPCAL_BENCHMARK_BUDGET_USD is required in benchmark mode"
        )
    return BenchmarkBudget(ceiling)


def create_app(
    provider: ExtractionProvider | None = None,
    oauth_broker: OAuthTokenBroker | None = None,
    benchmark_budget: BenchmarkBudget | None = None,
) -> FastAPI:
    selected_provider = provider or configured_provider()
    selected_oauth_broker = oauth_broker or configured_oauth_broker()
    benchmark_provider: BenchmarkExtractionProvider | None = None
    if benchmark_budget is not None:
        if not (
            hasattr(selected_provider, "extract_with_usage")
            and hasattr(selected_provider, "key_status")
        ):
            raise BenchmarkConfigurationError(
                "benchmark mode requires an OpenRouter provider with usage accounting"
            )
        benchmark_provider = selected_provider  # type: ignore[assignment]
    app = FastAPI(
        title="SnapCal Extraction API",
        version="0.1.0",
        docs_url=None,
        redoc_url=None,
        openapi_url=None,
    )

    @app.get("/health", response_model=HealthResponse)
    async def health() -> HealthResponse:
        return HealthResponse(model=selected_provider.model, ready=selected_provider.ready)

    @app.post("/v1/extract", response_model=ExtractionResponse)
    async def extract(request: ExtractionRequest) -> ExtractionResponse:
        try:
            events = await selected_provider.extract(request)
            return ExtractionResponse(model=selected_provider.model, events=events)
        except ProviderUnavailableError:
            raise HTTPException(
                status_code=503,
                detail={"code": "provider_unavailable", "message": "OpenRouter is unavailable."},
            ) from None
        except ProviderRejectedError:
            raise HTTPException(
                status_code=502,
                detail={"code": "provider_rejected", "message": "OpenRouter could not process this image."},
            ) from None
        except InvalidProviderOutputError:
            raise HTTPException(
                status_code=502,
                detail={"code": "invalid_provider_output", "message": "OpenRouter returned an invalid event proposal."},
            ) from None

    if benchmark_budget is not None and benchmark_provider is not None:
        @app.get(
            "/v1/benchmark/preflight",
            response_model=BenchmarkPreflightResponse,
        )
        async def benchmark_preflight() -> BenchmarkPreflightResponse:
            try:
                snapshot = await benchmark_budget.preflight(benchmark_provider)
                return BenchmarkPreflightResponse(
                    model=benchmark_provider.model,
                    budget_ceiling_usd=float(snapshot.budget_ceiling_usd),
                    provider_key_limit_usd=float(snapshot.provider_key_limit_usd),
                    provider_key_limit_remaining_usd=float(
                        snapshot.provider_key_limit_remaining_usd
                    ),
                    provider_key_limit_reset=snapshot.provider_key_limit_reset,
                )
            except (
                BenchmarkPreflightError,
                ProviderUnavailableError,
                ProviderRejectedError,
                InvalidProviderOutputError,
            ):
                raise HTTPException(
                    status_code=503,
                    detail={
                        "code": "benchmark_preflight_failed",
                        "message": "The benchmark provider budget could not be verified.",
                    },
                ) from None

        @app.get(
            "/v1/benchmark/status",
            response_model=BenchmarkStatusResponse,
        )
        async def benchmark_status() -> BenchmarkStatusResponse:
            snapshot = await benchmark_budget.status()
            return BenchmarkStatusResponse(
                model=benchmark_provider.model,
                usage=_benchmark_usage(snapshot),
            )

        @app.post(
            "/v1/benchmark/extract",
            response_model=BenchmarkExtractionResponse,
        )
        async def benchmark_extract(
            request: ExtractionRequest,
        ) -> BenchmarkExtractionResponse:
            try:
                result, usage = await benchmark_budget.extract(
                    benchmark_provider,
                    request,
                )
                return BenchmarkExtractionResponse(
                    model=benchmark_provider.model,
                    events=result.events,
                    usage=_benchmark_usage(usage),
                )
            except BenchmarkBudgetExceededError:
                raise HTTPException(
                    status_code=402,
                    detail={
                        "code": "benchmark_budget_exhausted",
                        "message": "The authorized benchmark budget is exhausted.",
                    },
                ) from None
            except ProviderUsageUnavailableError:
                raise HTTPException(
                    status_code=502,
                    detail={
                        "code": "benchmark_usage_unavailable",
                        "message": "OpenRouter request cost could not be verified.",
                    },
                ) from None
            except BenchmarkPreflightError:
                raise HTTPException(
                    status_code=503,
                    detail={
                        "code": "benchmark_preflight_failed",
                        "message": "The benchmark provider budget could not be verified.",
                    },
                ) from None
            except ProviderUnavailableError:
                raise HTTPException(
                    status_code=503,
                    detail={
                        "code": "provider_unavailable",
                        "message": "OpenRouter is unavailable.",
                    },
                ) from None
            except ProviderRejectedError:
                raise HTTPException(
                    status_code=502,
                    detail={
                        "code": "provider_rejected",
                        "message": "OpenRouter could not process this image.",
                    },
                ) from None
            except InvalidProviderOutputError:
                raise HTTPException(
                    status_code=502,
                    detail={
                        "code": "invalid_provider_output",
                        "message": "OpenRouter returned an invalid event proposal.",
                    },
                ) from None

    @app.post("/v1/google-oauth/token", response_model=OAuthTokenResponse)
    async def exchange_google_oauth_token(request: OAuthTokenRequest) -> OAuthTokenResponse:
        try:
            return await selected_oauth_broker.exchange(request)
        except OAuthBrokerUnavailableError:
            raise HTTPException(
                status_code=503,
                detail={
                    "code": "oauth_broker_unavailable",
                    "message": "Google OAuth helper is not configured.",
                },
            ) from None
        except OAuthClientMismatchError:
            raise HTTPException(
                status_code=400,
                detail={
                    "code": "oauth_client_mismatch",
                    "message": "Google OAuth credentials do not match SnapCal.",
                },
            ) from None
        except OAuthProviderRejectedError:
            raise HTTPException(
                status_code=400,
                detail={
                    "code": "oauth_exchange_rejected",
                    "message": "Google could not complete the OAuth token exchange.",
                },
            ) from None

    @app.exception_handler(ValueError)
    async def value_error_handler(_: Any, __: ValueError) -> JSONResponse:
        return JSONResponse(
            status_code=422,
            content={"detail": {"code": "invalid_request", "message": "The extraction request is invalid."}},
        )

    @app.exception_handler(RequestValidationError)
    async def request_validation_error_handler(_: Any, __: RequestValidationError) -> JSONResponse:
        return JSONResponse(
            status_code=422,
            content={"detail": {"code": "invalid_request", "message": "The request is invalid."}},
        )

    return app


def _benchmark_usage(snapshot: BenchmarkUsageSnapshot) -> BenchmarkUsage:
    return BenchmarkUsage(
        request_cost_usd=float(snapshot.request_cost_usd),
        cumulative_cost_usd=float(snapshot.cumulative_cost_usd),
        budget_remaining_usd=float(snapshot.budget_remaining_usd),
        request_count=snapshot.request_count,
    )


app = create_app(benchmark_budget=configured_benchmark_budget())
