# Exec Plan

## Goal

Add a fail-closed hosted `/v2` API and PostgreSQL usage layer while preserving
the loopback `/v1` development contract.

## Scope

In scope:

- Production configuration and secret boundaries.
- SQLAlchemy async models and Alembic migrations.
- Google identity exchange and rotating SnapCal device sessions.
- Authenticated multipart extraction with atomic reservation/finalization.
- Client-encrypted 15-minute retry envelopes and redacted audit metadata.
- Liveness/readiness endpoints and stable error codes.

Out of scope:

- Paddle checkout and webhook processing, owned by US-015.
- macOS account UI, owned by US-016.
- Provisioning live cloud resources, owned by US-017 and operator gates.

## Risk Classification

Risk flags:

- Auth.
- Authorization.
- Data model.
- Audit/security.
- External systems.
- Public contracts.
- Existing behavior.

Hard gates:

- Authentication and refresh-token reuse detection.
- Private screenshot-derived data retention.
- Provider invocation and quota accounting.

## Work Phases

1. Lock contracts and configuration.
2. Add schema and migration.
3. Add repositories and application services.
4. Mount `/v2` beside `/v1`.
5. Add unit, integration, privacy, and concurrency proof.
6. Record validation and Harness status.

## Stop Conditions

Pause if implementation would persist screenshot/OCR/plaintext results, make a
Calendar write, grant entitlement from unverified client state, or weaken the
two-transaction quota path.

