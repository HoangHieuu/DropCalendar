from __future__ import annotations

import os
from pathlib import Path
from typing import Any

from fastapi import FastAPI, HTTPException
from fastapi.responses import JSONResponse
from dotenv import load_dotenv

from .contracts import ExtractionRequest, ExtractionResponse, HealthResponse
from .provider import (
    ExtractionProvider,
    InvalidProviderOutputError,
    OpenRouterProvider,
    ProviderRejectedError,
    ProviderUnavailableError,
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


def create_app(provider: ExtractionProvider | None = None) -> FastAPI:
    selected_provider = provider or configured_provider()
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
            event = await selected_provider.extract(request)
            return ExtractionResponse(model=selected_provider.model, event=event)
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

    @app.exception_handler(ValueError)
    async def value_error_handler(_: Any, __: ValueError) -> JSONResponse:
        return JSONResponse(
            status_code=422,
            content={"detail": {"code": "invalid_request", "message": "The extraction request is invalid."}},
        )

    return app


app = create_app()
