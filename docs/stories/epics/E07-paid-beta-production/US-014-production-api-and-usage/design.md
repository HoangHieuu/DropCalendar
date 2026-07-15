# Design

## Domain Model

Users own device sessions, subscriptions, usage periods, extraction requests,
and audit records. A request moves through `reserved`, `succeeded`, `failed`,
or `expired`. Exactly one successful screenshot consumes one unit; all terminal
failure and fallback paths release their reservation.

## Application Flow

1. Bearer session and invitation/entitlement are validated.
2. The reserve transaction deduplicates the idempotency key and atomically
   checks quota, two concurrent requests, five requests/minute, and 30/day.
3. The image is validated in memory and the provider is called once.
4. The finalize transaction consumes or releases the reservation, records
   actual cost/timing, and stores only the sealed retry envelope.

## Interface Contract

US-014 owns `/v2/auth/google/exchange`, the authenticated transient
`/v2/auth/google/token` broker, `/v2/auth/session/refresh`,
`/v2/auth/logout`, `/v2/me`, `/v2/plans`, `/v2/extractions`,
`/v2/extractions/{request_id}`, `/health/live`, and `/health/ready`.
All failures use the redacted `error.code/message/retryable/request_id`
envelope.

## Data Model

PostgreSQL tables are `users`, `beta_invites`, `auth_sessions`, `plans`,
`subscriptions`, `usage_periods`, `extraction_requests`, `webhook_events`, and
`audit_events`. Identifiers and uniqueness are server-owned. Expiring envelopes
and 90-day operational metadata have indexed cleanup timestamps.

## UI / Platform Impact

No UI is added by this story. The API remains provider-neutral so future native
clients can reuse it.

## Observability

Record request ID, state, model, token counts, actual provider cost, durations,
quota outcome, and redacted audit action. Never record email, image bytes, OCR,
prompt, event fields, or credentials in logs.

## Alternatives Considered

1. Separate services: rejected until measured load requires them.
2. Paddle lookup on each request: rejected in favor of the local cache.
3. Store plaintext results: rejected because device-sealed retry is sufficient.
