# Design

## Domain Model

The plan defines quota and rate-limit features. A subscription is a lean cache
of Paddle identity, state, price, period, scheduled change, and last event time.

## Application Flow

Checkout and portal requests require an authenticated invited user. Webhook
ingestion verifies the raw signature, inserts a unique event ID, and delegates
idempotent processing. Entitlement reads use only the local cache.

## Interface Contract

`POST /v2/billing/checkout`, `POST /v2/billing/portal`, and
`POST /v2/webhooks/paddle` return stable redacted errors. Checkout returns a
hosted URL; the portal returns a short-lived hosted URL.

## Data Model

`plans`, `subscriptions`, and `webhook_events` store only access-control fields,
not payment instruments or full webhook bodies.

## UI / Platform Impact

The macOS app refreshes `/v2/me` after checkout but waits for webhook-owned
state before enabling Accuracy.

## Observability

Record event ID/type/occurred time, processing state, retry count, and redacted
failure category.

## Alternatives Considered

1. Client receipt authority: rejected because it is forgeable/stale.
2. Paddle lookup on hot path: rejected for latency and availability.

