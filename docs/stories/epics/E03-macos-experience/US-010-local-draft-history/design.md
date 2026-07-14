# Design

## Domain Model

`PersistedDraft` is a versioned boundary value containing normalized draft
fields, evidence excerpts, confidence and ambiguity state, extraction source,
and optional successful Calendar receipt. `RecentDraftSummary` exposes only the
small subset required by lists.

## Application Flow

- `save`: after extraction, after debounced user edits, and after Calendar
  success.
- `recent`: load bounded summaries at startup and after mutations.
- `open`: parse one stored payload and restore it to the existing review state.
- `delete`: remove one record only after an explicit user action.

Storage failures set a recoverable local-history notice and never authorize or
perform a Calendar write.

## Interface Contract

The inward-facing `DraftPersisting` protocol exposes asynchronous save, recent,
load, and delete operations. SQLite implementation details do not enter SwiftUI
or the domain model.

## Data Model

Schema version 1 owns one `drafts` table with stable UUID primary key, created
and updated timestamps, event start, normalized title/location, lifecycle
status, and a versioned JSON payload. An updated-time index serves recent lists;
title/start/location columns support a later duplicate-warning query.

The database contains no image bytes and no full OCR text. The containing
directory is owner-only and the database file uses mode `0600`.

## UI / Platform Impact

The ready/import view presents recent drafts. The menu-bar surface shows a
shorter recent list. Opening a row reveals the main window and enters the same
editable review flow. Deletion removes only the selected durable record.

## Observability

No event content or payload is logged. The UI may show a generic local-history
error. Tests inspect rows and filesystem permissions without printing private
field values.

## Alternatives Considered

1. `UserDefaults` and whole-draft archives were rejected in decision 0017.
