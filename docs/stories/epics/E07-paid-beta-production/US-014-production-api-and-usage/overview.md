# Overview

## Current Behavior

The loopback FastAPI helper exposes unauthenticated `/v1` JSON/base64
extraction. It has no product database, hosted identity, quota, rate limits,
idempotency, or production readiness contract.

## Target Behavior

The existing helper remains available for development. A separately configured
`/v2` modular-monolith API authenticates invited users, reserves and finalizes
one quota unit per successful screenshot, accepts bounded multipart JPEGs, and
stores only a device-encrypted result envelope for 15 minutes.

## Affected Users

- Anonymous Local Only users, whose offline path must not change.
- Invited Pro Beta users.
- Operators deploying staging and production.

## Affected Product Docs

- `docs/product/billing-release.md`
- `docs/product/extraction.md`
- `docs/product/privacy-quality.md`
- `docs/product/review-calendar.md`

## Non-Goals

- Model training or a new accuracy benchmark.
- Calendar event creation from the backend.
- Multiple microservices, Redis, object storage, or a general request queue.
