# 0024 Atomic Quota And Device-Sealed Retry

Date: 2026-07-15

## Status

Accepted

## Context

Paid Accuracy needs concurrency-safe accounting and short retry recovery without
retaining screenshots or readable screenshot-derived event data.

## Decision

- One screenshot reserves one unit and consumes it only after a valid non-empty
  result, regardless of the number of proposed events.
- The hot path uses one reserve transaction and one finalize transaction.
  Idempotency, entitlement, invitation, quota, two-concurrent, five-per-minute,
  and 30-per-day checks are atomic with reservation.
- Failure, rejection, timeout, invalid output, and Local Only fallback release
  the reservation and consume no user quota. Actual provider cost is still
  recorded as redacted operational metadata.
- The app creates an installation X25519 key pair and keeps the private key in
  Keychain. The service seals the structured result to the supplied public key
  before storing it.
- Only the sealed envelope is retained for 15 minutes. Screenshots, full OCR,
  prompts, plaintext event fields, and Google tokens are never persisted.
- Redacted cost, latency, model, status, and quota metadata expires after 90
  days after daily aggregation.

## Alternatives Considered

1. Charge before calling the provider. Rejected because failed requests must
   not consume quota.
2. Charge per extracted event. Rejected because the paid unit is a screenshot
   import and one source may legitimately contain multiple events.
3. Store plaintext retry JSON. Rejected because recovery does not require the
   service to read the result after returning it.
4. Add Redis or a general extraction queue. Rejected until measured beta load
   demonstrates a need.

## Consequences

Positive:

- Concurrent requests cannot overspend the user quota.
- Retry recovery has a bounded retention window and is device-confidential.

Tradeoffs:

- A lost installation key makes the retained envelope intentionally unusable.
- PostgreSQL row locking is required for production-grade concurrency proof.

## Follow-Up

- Enable a cache only if optimized quota transactions exceed 100 ms p95.

