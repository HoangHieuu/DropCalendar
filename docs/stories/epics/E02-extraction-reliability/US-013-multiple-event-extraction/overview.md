# US-013 Overview

## Current Behavior

SnapCal converts every imported screenshot into exactly one `EventDraft`. A
numbered announcement containing two independently dated sessions is collapsed
into one draft, and Local Only reports the other date as an ambiguity.

## Target Behavior

SnapCal extracts one or more evidence-bearing drafts from a single screenshot.
When multiple events are detected, review identifies the current event and lets
the user move between drafts. Every draft is edited, persisted, and confirmed
independently; SnapCal never performs an automatic or one-click batch Calendar
write.

## Affected Users

- macOS users importing Vietnamese, English, or mixed-language announcements
  that contain multiple independently dated events.

## Affected Product Docs

- `docs/product/extraction.md`
- `docs/product/event-draft.md`
- `docs/product/review-calendar.md`
- `docs/product/privacy-quality.md`
- `docs/ARCHITECTURE.md`
- `docs/TEST_MATRIX.md`

## Non-Goals

- Batch confirmation or a `Create All` Calendar action.
- Inventing missing clock times from words such as `tối` or `evening`.
- Arbitrarily splitting every numbered list; each proposed event needs its own
  visible date evidence.
- Editing the supplied `SPEC.md` source snapshot.

