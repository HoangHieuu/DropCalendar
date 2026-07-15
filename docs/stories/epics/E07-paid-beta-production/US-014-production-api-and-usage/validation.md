# Validation

## Proof Strategy

Use provider and identity fakes for deterministic contract tests, then run a
PostgreSQL-backed integration check for locking and migration behavior.

## Test Plan

| Layer | Cases |
| --- | --- |
| Unit | token hashing/rotation, authenticated transient Google token forwarding, error mapping, period math, envelope expiry |
| Integration | migrations, two-transaction quota path, idempotency, concurrency, owner-only retry |
| E2E | authenticated multipart request through fake provider |
| Platform | existing `/v1` helper remains compatible |
| Performance | bounded payload and query-count assertions |
| Logs/Audit | forbidden private fields absent from logs and audit metadata |

## Fixtures

Invited users, session/device pairs, subscription states, usage periods,
provider success/failure/timeout responses, and sealed-envelope byte strings.

## Commands

```text
.venv/bin/python -m pytest services/extraction-api/tests
.venv/bin/alembic -c services/extraction-api/alembic.ini upgrade head
```

## Acceptance Evidence

Implemented locally. PostgreSQL concurrency and 50-user load cases run in CI;
live hosted proof remains an activation gate.
