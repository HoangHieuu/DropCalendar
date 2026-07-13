# 0008 SnapCal Contract And First Slice

Date: 2026-07-13

## Status

Accepted

## Context

The repository received a 1,300-line SnapCal specification while its existing
product docs were generic placeholders. Without decomposition, future agents
would either repeatedly ingest the monolith or mistake the Harness template for
product truth. The spec also recommends a broad multi-platform system, but no
application exists yet.

## Decision

Preserve `SPEC.md` as the source snapshot and use focused `docs/product/*`,
active stories, executable proof, and accepted decisions as the living
contract.

Start implementation with a macOS-first vertical slice: manual image import,
Apple Vision local OCR, typed extraction boundary, editable review, and local
draft. Add Google Calendar creation as a separate high-risk slice once the
draft/review boundary is proven. Do not scaffold mobile or later phases early.

## Alternatives Considered

1. Keep the monolithic spec as the permanent operating manual.
2. Build the polished notch UI before proving extraction and review.
3. Scaffold macOS, iOS, Android, backend, and benchmark packages together.

## Consequences

Positive:

- Agents retrieve smaller, domain-specific contracts.
- The first build proves the highest-value path before polished intake UX.
- Future platforms reuse a stable event-draft contract.

Tradeoffs:

- Product docs must stay synchronized with accepted changes.
- The final provider and transport choices remain open until a bounded story.

## Follow-Up

- Intake the first E01 story and decide the Xcode target, draft schema, and
  Phase 1 extraction boundary.
