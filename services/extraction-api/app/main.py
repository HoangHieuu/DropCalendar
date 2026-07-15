from __future__ import annotations

import os
import uuid
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI, HTTPException, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from dotenv import load_dotenv

from .api_errors import APIError
from .api_v2 import create_v2_router
from .billing import BillingService, PaddleClient
from .config import ConfigurationError, ProductionSettings
from .database import Database
from .identity import GoogleIdentityBroker
from .production_service import ProductionService
from .tasks import (
    CloudTaskQueue,
    CloudTasksPaddleDispatcher,
    CloudTasksResultCleanupScheduler,
    InternalTaskAuthorizer,
)

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


SERVICE_DIRECTORY = Path(__file__).resolve().parent.parent
REPOSITORY_DIRECTORY = SERVICE_DIRECTORY.parent.parent
# Local development keeps shared configuration at the repository root while
# the production container has `/app` as its service root. Neither lookup may
# assume a fixed number of parent directories exists.
load_dotenv(REPOSITORY_DIRECTORY / ".env", override=False)
load_dotenv(SERVICE_DIRECTORY / ".env", override=False)

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
    production_service: ProductionService | None = None,
    billing_service: BillingService | None = None,
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
    selected_production_service = production_service
    task_queue: CloudTaskQueue | None = None
    task_authorizer: InternalTaskAuthorizer | None = None
    if selected_production_service is None:
        selected_production_service = configured_production_service(selected_provider)
    if (
        selected_production_service is not None
        and selected_production_service.settings.environment != "test"
    ):
        task_queue = CloudTaskQueue(selected_production_service.settings)
        selected_production_service.result_cleanup_scheduler = (
            CloudTasksResultCleanupScheduler(task_queue)
        )
        task_authorizer = InternalTaskAuthorizer(
            audience=selected_production_service.settings.api_base_url,
            service_account_email=(
                selected_production_service.settings.cloud_tasks_service_account or ""
            ),
        )
    selected_billing_service = billing_service
    if selected_billing_service is None and selected_production_service is not None:
        selected_billing_service = BillingService(
            settings=selected_production_service.settings,
            database=selected_production_service.database,
            paddle=PaddleClient(
                api_key=selected_production_service.settings.paddle_api_key,
                environment=selected_production_service.settings.paddle_environment,
                price_id=selected_production_service.settings.paddle_price_id,
            ),
            dispatcher=(
                CloudTasksPaddleDispatcher(task_queue)
                if task_queue is not None
                else None
            ),
        )

    @asynccontextmanager
    async def lifespan(_: FastAPI):
        yield
        if selected_production_service is not None:
            await selected_production_service.close()
        if selected_billing_service is not None:
            await selected_billing_service.close()
        if task_queue is not None:
            await task_queue.close()
        close_provider = getattr(selected_provider, "close", None)
        if close_provider is not None:
            await close_provider()

    app = FastAPI(
        title="SnapCal Extraction API",
        version="0.1.0",
        docs_url=None,
        redoc_url=None,
        openapi_url=None,
        lifespan=lifespan,
    )

    app.include_router(
        create_v2_router(
            selected_production_service,
            selected_billing_service,
            task_authorizer,
            selected_oauth_broker,
        )
    )

    @app.get("/health", response_model=HealthResponse)
    async def health() -> HealthResponse:
        return HealthResponse(model=selected_provider.model, ready=selected_provider.ready)

    @app.get("/health/live")
    async def health_live() -> dict[str, str]:
        return {"status": "ok"}

    @app.get("/health/ready")
    async def health_ready() -> JSONResponse:
        database_ready = (
            selected_production_service is not None
            and await selected_production_service.database.is_ready()
        )
        ready = bool(database_ready and selected_provider.ready)
        return JSONResponse(
            status_code=200 if ready else 503,
            content={
                "status": "ok" if ready else "unavailable",
                "database": bool(database_ready),
                "provider": bool(selected_provider.ready),
            },
        )

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

    @app.exception_handler(APIError)
    async def api_error_handler(_: Request, error: APIError) -> JSONResponse:
        return JSONResponse(
            status_code=error.status_code,
            content={
                "error": {
                    "code": error.code,
                    "message": error.message,
                    "retryable": error.retryable,
                    "request_id": str(error.request_id),
                }
            },
        )

    @app.exception_handler(ValueError)
    async def value_error_handler(request: Request, __: ValueError) -> JSONResponse:
        if request.url.path.startswith("/v2/"):
            return JSONResponse(
                status_code=422,
                content={
                    "error": {
                        "code": "invalid_request",
                        "message": "The request is invalid.",
                        "retryable": False,
                        "request_id": str(uuid.uuid4()),
                    }
                },
            )
        return JSONResponse(
            status_code=422,
            content={"detail": {"code": "invalid_request", "message": "The extraction request is invalid."}},
        )

    @app.exception_handler(RequestValidationError)
    async def request_validation_error_handler(request: Request, __: RequestValidationError) -> JSONResponse:
        if request.url.path.startswith("/v2/"):
            request_id = str(uuid.uuid4())
            return JSONResponse(
                status_code=422,
                content={
                    "error": {
                        "code": "invalid_request",
                        "message": "The request is invalid.",
                        "retryable": False,
                        "request_id": request_id,
                    }
                },
            )
        return JSONResponse(
            status_code=422,
            content={"detail": {"code": "invalid_request", "message": "The request is invalid."}},
        )

    @app.exception_handler(Exception)
    async def unhandled_error_handler(request: Request, __: Exception) -> JSONResponse:
        if request.url.path.startswith("/v2/"):
            return JSONResponse(
                status_code=500,
                content={
                    "error": {
                        "code": "internal_error",
                        "message": "SnapCal could not complete the request.",
                        "retryable": True,
                        "request_id": str(uuid.uuid4()),
                    }
                },
            )
        return JSONResponse(
            status_code=500,
            content={
                "detail": {
                    "code": "internal_error",
                    "message": "SnapCal could not complete the request.",
                }
            },
        )

    return app


def configured_production_service(
    provider: ExtractionProvider,
) -> ProductionService | None:
    settings = ProductionSettings.from_environment()
    if settings is None:
        return None
    if not (
        hasattr(provider, "extract_with_usage")
        and hasattr(provider, "key_status")
    ):
        raise ConfigurationError(
            "production mode requires provider usage accounting"
        )
    credential_path = os.environ.get("GOOGLE_OAUTH_CREDENTIALS_FILE", "").strip()
    if not credential_path:
        raise ConfigurationError(
            "GOOGLE_OAUTH_CREDENTIALS_FILE is required in production mode"
        )
    identity = GoogleIdentityBroker(Path(credential_path))
    return ProductionService(
        settings=settings,
        database=Database(settings),
        identity=identity,
        provider=provider,  # type: ignore[arg-type]
    )


def _benchmark_usage(snapshot: BenchmarkUsageSnapshot) -> BenchmarkUsage:
    return BenchmarkUsage(
        request_cost_usd=float(snapshot.request_cost_usd),
        cumulative_cost_usd=float(snapshot.cumulative_cost_usd),
        budget_remaining_usd=float(snapshot.budget_remaining_usd),
        request_count=snapshot.request_count,
    )


app = create_app(benchmark_budget=configured_benchmark_budget())
