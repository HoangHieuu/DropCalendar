# Design

## Domain Model

The draft adds typed reminder overrides and a source fingerprint. Pure reminder
and duplicate policies produce suggestions/warnings. Location candidates are
ephemeral review proposals and become a user edit only after selection.

## Application Flow

- Suggest reminders after extraction, then validate them during pure Calendar
  mapping.
- Compute duplicate warnings against local persisted drafts before save and
  again after edits.
- Search MapKit only from an explicit Find Places action; selecting a result
  updates the editable location field.
- Retain a screenshot only when the default-off setting is enabled; encrypt it
  before any filesystem write.
- Per-item Delete and Clear All remove SnapCal-owned records; neither touches a
  Google event or the original source image.

## Interface Contract

Google Calendar payloads set `reminders.useDefault=false` and include validated
overrides. MapKit and screenshot storage sit behind inward-facing protocols.

## Data Model

The existing draft payload gains reminders and a source fingerprint. SQLite
adds an indexed source-fingerprint column before schema version 1 is released.
Encrypted screenshot files are keyed by draft UUID and are not SQLite blobs.

## UI / Platform Impact

Review adds reminder chips/editing, duplicate warnings, location-candidate
selection, and optional encrypted screenshot evidence. Settings adds the
history toggle and destructive Clear All confirmation.

## Observability

No reminder title, location query/result, image bytes, OCR, or encryption key is
logged. Errors use redacted categories only.

## Alternatives Considered

See decision 0018.
