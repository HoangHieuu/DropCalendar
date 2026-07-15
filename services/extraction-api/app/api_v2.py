from __future__ import annotations

import json
import uuid
from time import monotonic
from fastapi import APIRouter, Body, Depends, File, Form, Header, Request, Response, Security, UploadFile
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pydantic import ValidationError

from .api_errors import APIError
from .billing import BillingService
from .contracts import OAuthTokenRequest, OAuthTokenResponse
from .contracts_v2 import (
    GoogleExchangeRequest,
    GoogleExchangeResponse,
    HostedURLResponse,
    MeResponse,
    PlanResponse,
    RetryEnvelopeResponse,
    SessionRefreshRequest,
    SessionTokens,
    V2ExtractionMetadata,
    V2ExtractionResponse,
    WebhookAcceptedResponse,
    MAX_V2_IMAGE_BYTES,
)
from .production_service import ProductionService
from .oauth_broker import (
    OAuthBrokerUnavailableError,
    OAuthClientMismatchError,
    OAuthProviderRejectedError,
    OAuthTokenBroker,
)
from .security import AccessClaims
from .tasks import InternalTaskAuthorizer, paddle_projection_from_payload


bearer = HTTPBearer(auto_error=False)


def create_v2_router(
    service: ProductionService | None,
    billing: BillingService | None = None,
    task_authorizer: InternalTaskAuthorizer | None = None,
    oauth_broker: OAuthTokenBroker | None = None,
) -> APIRouter:
    router = APIRouter(prefix="/v2")

    def required_service() -> ProductionService:
        if service is None:
            raise APIError(
                code="service_unavailable",
                message="SnapCal's hosted service is not configured.",
                status_code=503,
                retryable=True,
            )
        return service

    def required_billing() -> BillingService:
        if billing is None:
            raise APIError(
                code="billing_unavailable",
                message="SnapCal billing is not configured.",
                status_code=503,
                retryable=True,
            )
        return billing

    def required_oauth_broker() -> OAuthTokenBroker:
        if oauth_broker is None:
            raise APIError(
                code="oauth_broker_unavailable",
                message="Google OAuth is not configured.",
                status_code=503,
                retryable=True,
            )
        return oauth_broker

    async def authorize_task(authorization: str | None) -> None:
        if task_authorizer is None:
            raise APIError(
                code="internal_task_unavailable",
                message="Internal task processing is not configured.",
                status_code=503,
                retryable=True,
            )
        await task_authorizer.authorize(authorization)

    async def claims(
        credentials: HTTPAuthorizationCredentials | None = Security(bearer),
    ) -> AccessClaims:
        selected = required_service()
        if credentials is None or credentials.scheme.lower() != "bearer":
            raise APIError(
                code="authentication_required",
                message="Sign in to continue.",
                status_code=401,
            )
        return selected.decode_access_token(credentials.credentials)

    @router.post("/auth/google/exchange", response_model=GoogleExchangeResponse)
    async def google_exchange(request: GoogleExchangeRequest) -> GoogleExchangeResponse:
        return await required_service().exchange_google(request)

    @router.post("/auth/session/refresh", response_model=SessionTokens)
    async def session_refresh(request: SessionRefreshRequest) -> SessionTokens:
        return await required_service().refresh_session(request.refresh_token)

    @router.post("/auth/google/token", response_model=OAuthTokenResponse)
    async def google_token(
        request: OAuthTokenRequest,
        _: AccessClaims = Depends(claims),
    ) -> OAuthTokenResponse:
        """Exchange Google tokens transiently for an authenticated installation."""

        try:
            return await required_oauth_broker().exchange(request)
        except OAuthBrokerUnavailableError:
            raise APIError(
                code="oauth_broker_unavailable",
                message="Google OAuth is temporarily unavailable.",
                status_code=503,
                retryable=True,
            ) from None
        except OAuthClientMismatchError:
            raise APIError(
                code="oauth_client_mismatch",
                message="Google OAuth configuration does not match this app.",
                status_code=400,
            ) from None
        except OAuthProviderRejectedError:
            raise APIError(
                code="oauth_exchange_rejected",
                message="Google rejected the token exchange.",
                status_code=400,
            ) from None

    @router.post("/auth/logout", status_code=204)
    async def logout(current: AccessClaims = Depends(claims)) -> Response:
        await required_service().logout(current)
        return Response(status_code=204)

    @router.get("/me", response_model=MeResponse)
    async def me(current: AccessClaims = Depends(claims)) -> MeResponse:
        return await required_service().me(current)

    @router.get("/plans", response_model=list[PlanResponse])
    async def plans() -> list[PlanResponse]:
        return await required_service().plans()

    @router.post("/billing/checkout", response_model=HostedURLResponse)
    async def billing_checkout(
        current: AccessClaims = Depends(claims),
    ) -> HostedURLResponse:
        return await required_billing().checkout(current)

    @router.post("/billing/portal", response_model=HostedURLResponse)
    async def billing_portal(
        current: AccessClaims = Depends(claims),
    ) -> HostedURLResponse:
        return await required_billing().portal(current)

    @router.post("/webhooks/paddle", response_model=WebhookAcceptedResponse)
    async def paddle_webhook(
        request: Request,
        paddle_signature: str | None = Header(default=None, alias="Paddle-Signature"),
    ) -> WebhookAcceptedResponse:
        return await required_billing().ingest_webhook(
            raw_body=await request.body(),
            signature=paddle_signature,
        )

    @router.post("/extractions", response_model=V2ExtractionResponse)
    async def extract(
        current: AccessClaims = Depends(claims),
        idempotency_key: str | None = Header(default=None, alias="Idempotency-Key"),
        metadata_json: str = Form(default="", alias="metadata"),
        image: UploadFile | None = File(default=None),
    ) -> V2ExtractionResponse:
        selected = required_service()
        if idempotency_key is None or not (8 <= len(idempotency_key.strip()) <= 128):
            raise APIError(
                code="invalid_idempotency_key",
                message="A valid Idempotency-Key header is required.",
                status_code=422,
            )
        if image is None or image.content_type != "image/jpeg":
            raise APIError(
                code="invalid_image",
                message="Accuracy accepts one JPEG image.",
                status_code=422,
            )
        try:
            metadata = V2ExtractionMetadata.model_validate_json(metadata_json)
        except (ValidationError, ValueError, json.JSONDecodeError):
            raise APIError(
                code="invalid_request",
                message="Accuracy metadata is invalid.",
                status_code=422,
            ) from None
        image_bytes = await image.read(MAX_V2_IMAGE_BYTES + 1)
        await image.close()
        if (
            not image_bytes
            or len(image_bytes) > MAX_V2_IMAGE_BYTES
            or not image_bytes.startswith(b"\xff\xd8\xff")
        ):
            raise APIError(
                code="invalid_image",
                message="The JPEG must be valid and no larger than 4 MiB.",
                status_code=422,
            )
        started_at = monotonic()
        try:
            reservation = await selected.reserve(
                claims=current,
                idempotency_key=idempotency_key.strip(),
                image=image_bytes,
            )
        except APIError as error:
            try:
                await selected.record_reservation_denial(current, error.code)
            except Exception:
                # Auditing is best-effort and must never replace the stable
                # denial the user should receive.
                pass
            raise
        return await selected.run_extraction(
            claims=current,
            reservation=reservation,
            image=image_bytes,
            metadata=metadata,
            started_at=started_at,
        )

    @router.get(
        "/extractions/{request_id}", response_model=RetryEnvelopeResponse
    )
    async def retry_envelope(
        request_id: uuid.UUID,
        current: AccessClaims = Depends(claims),
    ) -> RetryEnvelopeResponse:
        return await required_service().retry_envelope(current, request_id)

    @router.post("/internal/tasks/paddle", status_code=204, include_in_schema=False)
    async def process_paddle_task(
        payload: dict = Body(...),
        authorization: str | None = Header(default=None),
    ) -> Response:
        await authorize_task(authorization)
        await required_billing().apply_webhook(
            paddle_projection_from_payload(payload)
        )
        return Response(status_code=204)

    @router.post(
        "/internal/tasks/expire-result", status_code=204, include_in_schema=False
    )
    async def expire_result_task(
        payload: dict = Body(...),
        authorization: str | None = Header(default=None),
    ) -> Response:
        await authorize_task(authorization)
        try:
            request_id = uuid.UUID(str(payload["request_id"]))
        except (KeyError, TypeError, ValueError):
            raise APIError(
                code="invalid_task_payload",
                message="The internal task payload is invalid.",
                status_code=400,
            ) from None
        await required_service().expire_retry_envelope(request_id)
        return Response(status_code=204)

    @router.post(
        "/internal/maintenance/daily", status_code=204, include_in_schema=False
    )
    async def daily_maintenance(
        authorization: str | None = Header(default=None),
    ) -> Response:
        await authorize_task(authorization)
        await required_service().run_daily_maintenance()
        return Response(status_code=204)

    return router
