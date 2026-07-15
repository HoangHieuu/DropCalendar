# US-013 Design

## Domain Model

- Local and Accuracy extraction return a non-empty ordered collection of
  `EventDraft` values.
- Every draft keeps its own field evidence, confidence, ambiguities, reminders,
  persistence identity, and Calendar lifecycle.
- Drafts from one screenshot receive deterministic per-position source
  fingerprints so sibling events are not treated as duplicates while importing
  the same screenshot again can still be detected.

## Application Flow

1. Validate one supported screenshot and run Apple Vision OCR once.
2. Local Only detects independently dated numbered blocks and otherwise keeps
   the existing single-event fallback.
3. Accuracy Mode asks the provider for one or more event proposals and strictly
   validates every proposal.
4. Reconcile provider drafts with the corresponding local drafts when a safe
   positional match exists; otherwise preserve provider evidence and surface
   disagreement or fallback clearly.
5. Persist each normalized draft and show the first in review.
6. Let the user move among drafts only while no confirmation or Calendar
   operation is active.
7. Require a separate confirmation and `events.insert` call for each draft.

## Interface Contract

- `POST /v1/extract` keeps its route and request shape and returns response
  schema version 2 with `events`, an array of 1 to 10 strict proposals.
- The macOS decoder also accepts the version-1 single `event` response during a
  local service/app rolling upgrade.
- Provider output is a strict object containing `events`; an empty list,
  over-limit list, or invalid member fails closed.

## Data Model

No database migration is required. Each event remains an independent versioned
draft row. Screenshot history remains opt-in; when enabled, the same source may
be encrypted under each extracted draft identity so every draft retains an
independently deletable preview.

## UI / Platform Impact

- Review shows `Event N of M` and focused previous/next controls when `M > 1`.
- Edits update only the selected draft.
- Created/failed Calendar state is restored independently when switching among
  drafts.
- Existing single-event review is visually unchanged when `M == 1`.

## Observability

Allowed metrics add event proposal count and selected draft ordinal. Logs still
exclude image bytes, OCR text, provider content, and private event details.

## Alternatives Considered

1. One combined Calendar event: rejected because the dates and sessions are
   independently actionable.
2. `Create All` after one confirmation: rejected because it weakens the
   explicit-confirmation boundary for each external write.
3. Store a new import-group table first: deferred because independent draft
   rows and in-memory review grouping satisfy this bounded slice without a
   migration.

