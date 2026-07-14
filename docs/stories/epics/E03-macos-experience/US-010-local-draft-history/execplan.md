# Exec Plan

## Goal

Deliver safe, reopenable local draft history for the Phase 3 macOS workflow.

## Scope

In scope:

- Versioned SQLite schema and repository.
- Save on extraction, edit, and successful creation.
- Recent list, reopen, and explicit deletion.
- Privacy and migration tests.

Out of scope:

- Screenshot retention, cloud sync, and duplicate warning UI.

## Risk Classification

Risk flags:

- Data model.
- Audit/security and privacy.
- Existing review behavior.
- Data deletion.

Hard gates:

- Data loss and privacy.

Direction is supplied by accepted product docs and decision 0017: deletion is
explicit, migrations are versioned, and image/full-OCR retention is prohibited.

## Work Phases

1. Lock persistence and retention decision.
2. Add typed store boundary and schema version 1.
3. Integrate model lifecycle with debounced saves.
4. Add recent/reopen/delete UI.
5. Run unit, integration, app-build, and privacy proof.
6. Update Harness evidence.

## Stop Conditions

Pause for human confirmation if an existing released schema needs destructive
migration, deletion would become implicit, or screenshot retention becomes
necessary.
