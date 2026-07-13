# US-003 Exec Plan

## Goal

Correctly propose a reviewable all-day date range and visual title from the
Agentic AI Build Week poster while preserving privacy, evidence, and local-only
behavior.

## Scope

In scope:

- Layout-aware Apple Vision observations.
- Versioned FastAPI extraction proxy and Gemini 2.5 Flash adapter.
- Strict structured-output contract parsing.
- Opt-in Accuracy Mode, visible source/fallback UI, and local-only enforcement.
- Deterministic provider/client/state tests using the supplied poster fixture.
- Inclusive all-day review-end semantics.

Out of scope:

- Production deployment and Secret Manager.
- Cloud OCR, geocoding, persistence, and benchmark-wide accuracy claims.
- Live Gemini proof until the user supplies a dedicated authorization key.

## Risk Classification

Risk flags:

- Audit/security.
- External systems.
- Public contracts.
- Existing behavior.
- Weak proof.
- Multi-domain.

Hard gates:

- External provider behavior.
- Private screenshot cloud processing.

## Work Phases

1. Lock proxy, secret, consent, schema, and fallback decisions.
2. Add layout evidence and correct local all-day/date-range semantics.
3. Add the backend contract and Gemini adapter.
4. Add the macOS client, application state, and UI disclosure.
5. Add deterministic Python and XCTest proof including the supplied poster.
6. Build, launch, audit, and leave live-provider setup as an explicit handoff.

## Stop Conditions

Pause for human confirmation if:

- A provider secret would need to enter the app or repository.
- Cloud processing cannot be clearly disabled.
- The model requires inventing missing dates or times.
- Calendar confirmation behavior would be weakened.
