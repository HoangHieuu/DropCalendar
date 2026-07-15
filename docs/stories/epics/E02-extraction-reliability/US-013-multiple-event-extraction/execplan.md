# US-013 Exec Plan

## Goal

Extract and safely create both independently dated events from one screenshot
without weakening review, evidence, privacy, or Calendar confirmation.

## Scope

In scope:

- Multiple local and Accuracy proposals from one screenshot.
- Ordered multi-draft application state and focused review navigation.
- Independent persistence, duplicate identity, edit state, and Calendar state.
- Strict schema-v2 service/client contract with version-1 client compatibility.
- Deterministic XCTest and pytest proof.

Out of scope:

- Batch Calendar writes or one confirmation covering multiple events.
- Semantic on-device LLM work beyond conservative numbered-block grouping.
- Real paid provider or Google Calendar side effects during tests.

## Risk Classification

Risk flags:

- Public contracts.
- Data model.
- Audit/security.
- External systems.
- Existing behavior.
- Weak proof.
- Multi-domain.

Hard gates:

- Every external Calendar write retains its own explicit confirmation.
- No date or clock time is invented without evidence.
- Local Only performs no cloud request.
- The app and service fail closed on empty or invalid provider collections.

## Work Phases

1. Record the SPEC extension and multi-write safety boundary.
2. Add ordered local and provider multi-event contracts.
3. Add application grouping, per-draft persistence, and review navigation.
4. Add deterministic unit, integration, and safety tests.
5. Run Python and macOS verification.
6. Update product truth and Harness evidence.

## Stop Conditions

Pause for human confirmation if:

- Calendar writes cannot remain independently confirmed.
- A database migration or destructive history rewrite becomes necessary.
- Missing time evidence would need to be guessed.
- Provider compatibility requires exposing private content or credentials.

