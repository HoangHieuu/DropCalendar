# 0017 Private Local Draft Persistence

Date: 2026-07-14

## Status

Accepted

## Context

Phase 3 requires recent drafts to survive window closure and app relaunch.
Drafts contain private event details, extraction evidence, and potentially
sensitive screenshot metadata. Raw screenshots and full OCR text are not
required to reopen a normalized draft.

## Decision

- Store normalized draft metadata in a product-owned SQLite database under
  SnapCal's Application Support directory.
- Create the Application Support directory with owner-only permissions and the
  database with mode `0600`.
- Use an explicit schema version and reject databases created by a newer app.
- Persist a versioned JSON payload inside a typed `drafts` table. Indexed
  columns retain stable identity, update time, event start, normalized title,
  normalized location, and lifecycle status for recent-history and future
  duplicate queries.
- Never persist image bytes or full OCR text. Preserve only normalized fields,
  field-level evidence excerpts, confidence, inference/edit flags, and
  structured ambiguity messages needed for review.
- Keep records until the user explicitly deletes them. Do not silently expire
  history in the first persistence version.
- Run SQLite work outside the main actor and surface recoverable storage errors
  without blocking extraction, review, or Calendar confirmation.

## Alternatives Considered

1. `UserDefaults`. Rejected because it lacks migrations, bounded queries, and
   safe structured deletion.
2. Persist the complete screenshot and OCR output. Rejected because reopening a
   normalized draft does not justify retaining those sensitive inputs.
3. Automatically delete older drafts. Deferred because an implicit retention
   limit would delete user data without an established product setting.
4. A server database. Rejected because recent drafts are local product state
   and do not require an account or network dependency.

## Consequences

- Relaunch, reopen, and explicit history deletion can be tested locally.
- Later duplicate detection has bounded local query keys.
- Reopened drafts retain field evidence but do not expose the full original OCR
  transcript.
- A future schema change must add a tested migration instead of mutating version
  1 in place after release.
- Phase 4 introduced schema version 2 for the source fingerprint; existing
  version-1 databases migrate transactionally and retain their draft records.

## Verification

```text
xcodebuild -project SnapCal.xcodeproj -scheme SnapCal -destination 'platform=macOS' -derivedDataPath .build/DerivedData -only-testing:SnapCalTests/SQLiteDraftStoreTests -only-testing:SnapCalTests/SnapCalModelTests test
```
