from __future__ import annotations

import asyncio
import hashlib
import json
import uuid
from datetime import UTC, datetime
from typing import Any

from google.auth.transport.requests import Request as GoogleAuthRequest
from google.oauth2 import id_token

from .api_errors import APIError
from .billing import PaddleWebhookProjection
from .config import ProductionSettings


class CloudTaskDispatchError(RuntimeError):
    pass


class InternalTaskAuthorizer:
    """Validates the OIDC token Cloud Tasks or Scheduler attaches to a request."""

    def __init__(self, *, audience: str, service_account_email: str) -> None:
        self.audience = audience
        self.service_account_email = service_account_email

    async def authorize(self, authorization: str | None) -> None:
        if authorization is None or not authorization.startswith("Bearer "):
            raise _task_authentication_error()
        token = authorization.removeprefix("Bearer ").strip()
        if not token:
            raise _task_authentication_error()
        try:
            claims = await asyncio.to_thread(
                id_token.verify_oauth2_token,
                token,
                GoogleAuthRequest(),
                self.audience,
            )
        except Exception:
            raise _task_authentication_error() from None
        issuer = claims.get("iss")
        email = claims.get("email")
        if (
            issuer not in {"accounts.google.com", "https://accounts.google.com"}
            or email != self.service_account_email
            or claims.get("email_verified") is not True
        ):
            raise _task_authentication_error()


class CloudTaskQueue:
    """One process-level Cloud Tasks client for webhook and cleanup work."""

    def __init__(self, settings: ProductionSettings) -> None:
        if not all(
            (
                settings.cloud_tasks_project,
                settings.cloud_tasks_location,
                settings.cloud_tasks_queue,
                settings.cloud_tasks_service_account,
            )
        ):
            raise CloudTaskDispatchError("Cloud Tasks is not configured")
        # Import lazily so local-only and unit-test environments do not need ADC.
        from google.cloud import tasks_v2

        self._tasks_v2 = tasks_v2
        self._client = tasks_v2.CloudTasksClient()
        self._project = settings.cloud_tasks_project
        self._location = settings.cloud_tasks_location
        self._queue = settings.cloud_tasks_queue
        self._service_account = settings.cloud_tasks_service_account
        self._audience = settings.api_base_url
        self._base_url = settings.api_base_url

    async def close(self) -> None:
        close = getattr(self._client, "close", None)
        if close is not None:
            await asyncio.to_thread(close)

    async def enqueue(
        self,
        *,
        path: str,
        payload: dict[str, Any],
        task_key: str,
        schedule_at: datetime | None = None,
    ) -> None:
        tasks_v2 = self._tasks_v2
        parent = self._client.queue_path(
            self._project, self._location, self._queue
        )
        task_id = _task_id(task_key)
        task = tasks_v2.Task(
            name=f"{parent}/tasks/{task_id}",
            http_request=tasks_v2.HttpRequest(
                http_method=tasks_v2.HttpMethod.POST,
                url=f"{self._base_url}{path}",
                headers={"Content-Type": "application/json"},
                oidc_token=tasks_v2.OidcToken(
                    service_account_email=self._service_account,
                    audience=self._audience,
                ),
                body=json.dumps(
                    payload, separators=(",", ":"), sort_keys=True
                ).encode("utf-8"),
            ),
        )
        if schedule_at is not None:
            normalized = schedule_at.astimezone(UTC)
            task.schedule_time = normalized
        request = tasks_v2.CreateTaskRequest(parent=parent, task=task)
        try:
            await asyncio.to_thread(self._client.create_task, request=request)
        except Exception as error:
            # A deterministic task name makes redelivery idempotent. Existing tasks
            # are success; all other failures are retried by the webhook sender or
            # covered by the daily cleanup sweep.
            if error.__class__.__name__ == "AlreadyExists":
                return
            raise CloudTaskDispatchError("Cloud Task could not be queued") from error


class CloudTasksPaddleDispatcher:
    def __init__(self, queue: CloudTaskQueue) -> None:
        self.queue = queue

    async def dispatch(self, projection: PaddleWebhookProjection) -> None:
        await self.queue.enqueue(
            path="/v2/internal/tasks/paddle",
            payload=paddle_projection_payload(projection),
            task_key=f"paddle-{projection.event_id}",
        )


class CloudTasksResultCleanupScheduler:
    def __init__(self, queue: CloudTaskQueue) -> None:
        self.queue = queue

    async def schedule_result_cleanup(
        self, request_id: uuid.UUID, expires_at: datetime
    ) -> None:
        await self.queue.enqueue(
            path="/v2/internal/tasks/expire-result",
            payload={"request_id": str(request_id)},
            task_key=f"expire-{request_id}",
            schedule_at=expires_at,
        )


def paddle_projection_payload(
    projection: PaddleWebhookProjection,
) -> dict[str, Any]:
    return {
        "event_id": projection.event_id,
        "event_type": projection.event_type,
        "occurred_at": projection.occurred_at.isoformat(),
        "subscription_id": projection.subscription_id,
        "customer_id": projection.customer_id,
        "status": projection.status,
        "product_id": projection.product_id,
        "price_id": projection.price_id,
        "period_start": projection.period_start.isoformat(),
        "period_end": projection.period_end.isoformat(),
        "scheduled_change": projection.scheduled_change,
        "scheduled_change_effective_at": (
            projection.scheduled_change_effective_at.isoformat()
            if projection.scheduled_change_effective_at is not None
            else None
        ),
        "snapcal_user_id": (
            str(projection.snapcal_user_id)
            if projection.snapcal_user_id is not None
            else None
        ),
    }


def paddle_projection_from_payload(payload: dict[str, Any]) -> PaddleWebhookProjection:
    try:
        return PaddleWebhookProjection(
            event_id=_required_string(payload, "event_id"),
            event_type=_required_string(payload, "event_type"),
            occurred_at=_timestamp(payload["occurred_at"]),
            subscription_id=_required_string(payload, "subscription_id"),
            customer_id=_required_string(payload, "customer_id"),
            status=_required_string(payload, "status"),
            product_id=_required_string(payload, "product_id"),
            price_id=_required_string(payload, "price_id"),
            period_start=_timestamp(payload["period_start"]),
            period_end=_timestamp(payload["period_end"]),
            scheduled_change=_optional_string(payload.get("scheduled_change")),
            scheduled_change_effective_at=(
                _timestamp(payload["scheduled_change_effective_at"])
                if payload.get("scheduled_change_effective_at") is not None
                else None
            ),
            snapcal_user_id=(
                uuid.UUID(payload["snapcal_user_id"])
                if payload.get("snapcal_user_id") is not None
                else None
            ),
        )
    except (KeyError, TypeError, ValueError):
        raise APIError(
            code="invalid_task_payload",
            message="The internal task payload is invalid.",
            status_code=400,
        ) from None


def _task_id(value: str) -> str:
    return "snapcal-" + hashlib.sha256(value.encode("utf-8")).hexdigest()


def _timestamp(value: Any) -> datetime:
    if not isinstance(value, str):
        raise TypeError("timestamp")
    result = datetime.fromisoformat(value.replace("Z", "+00:00"))
    if result.tzinfo is None:
        raise ValueError("timezone required")
    return result.astimezone(UTC)


def _required_string(payload: dict[str, Any], key: str) -> str:
    value = payload[key]
    if not isinstance(value, str) or not value.strip():
        raise TypeError(key)
    return value.strip()


def _optional_string(value: Any) -> str | None:
    if value is None:
        return None
    if not isinstance(value, str) or not value.strip():
        raise TypeError("optional string")
    return value.strip()


def _task_authentication_error() -> APIError:
    return APIError(
        code="internal_task_unauthorized",
        message="The internal task is not authorized.",
        status_code=401,
    )
