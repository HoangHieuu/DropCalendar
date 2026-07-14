# US-010 Local Draft History

## Status

implemented; relaunch behavior is integration-proven and remains in the manual
release smoke checklist

## Previous Behavior

Drafts exist only in the shared in-memory `SnapCalModel`. Starting over or
relaunching the app removes access to the review state.

## Implemented Behavior

Successful extraction and subsequent user edits update a private local SQLite
record. The import and menu-bar surfaces list recent drafts, support reopening a
draft into mandatory review, and let the user explicitly delete a history
record. No screenshot bytes or full OCR transcript enter the database.

## Affected Users

- macOS users importing and reviewing Vietnamese-English event screenshots.

## Affected Product Docs

- `docs/product/event-draft.md`
- `docs/product/privacy-quality.md`
- `docs/product/review-calendar.md`
- `docs/product/platform-roadmap.md`

## Non-Goals

- Screenshot history.
- Cloud synchronization or accounts.
- Automatic retention expiry.
- Broader Google Calendar history reads.
