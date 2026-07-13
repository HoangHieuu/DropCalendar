from __future__ import annotations

import os
from typing import Any

from fastapi import FastAPI, HTTPException
from fastapi.responses import JSONResponse

from .contracts import ExtractionRequest, ExtractionResponse, HealthResponse
from .provider import (
    ExtractionProvider,
    GeminiProvider,
    InvalidProviderOutputError,
    ProviderRejectedError,
    ProviderUnavailableError,
    UnavailableGeminiProvider,
)


DEFAULT_MODEL = "gemini-2.5-flash"


def configured_provider() -> ExtractionProvider:
    model = os.environ.get("SNAPCAL_GEMINI_MODEL", DEFAULT_MODEL).strip() or DEFAULT_MODEL
    api_key = os.environ.get("GEMINI_API_KEY", "").strip()
    if not api_key:
        return UnavailableGeminiProvider(model=model)
    try:
        return GeminiProvider(api_key=api_key, model=model)
    except ProviderUnavailableError:
        return UnavailableGeminiProvider(model=model)


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
        except ProviderUnavailableError as error:
            raise HTTPException(
                status_code=503,
                detail={"code": "provider_unavailable", "message": str(error)},
            ) from None
        except ProviderRejectedError:
            raise HTTPException(
                status_code=502,
                detail={"code": "provider_rejected", "message": "Gemini could not process this image."},
            ) from None
        except InvalidProviderOutputError:
            raise HTTPException(
                status_code=502,
                detail={"code": "invalid_provider_output", "message": "Gemini returned an invalid event proposal."},
            ) from None

    @app.exception_handler(ValueError)
    async def value_error_handler(_: Any, __: ValueError) -> JSONResponse:
        return JSONResponse(
            status_code=422,
            content={"detail": {"code": "invalid_request", "message": "The extraction request is invalid."}},
        )

    return app


app = create_app()
