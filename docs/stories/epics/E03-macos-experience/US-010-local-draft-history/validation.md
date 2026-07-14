# Validation

## Proof Strategy

Prove typed round-trip, relaunch through a fresh store instance, explicit
deletion, schema rejection, file permissions, payload minimization, model
integration, and unchanged Calendar confirmation boundaries.

## Test Plan

| Layer | Cases |
| --- | --- |
| Unit | versioned payload encode/decode and malformed-row rejection |
| Integration | save/reopen across store instances; update; explicit delete; SQLite permissions |
| E2E | import, edit, return to ready, reopen from Recent Drafts, delete |
| Platform | macOS app build and menu-bar/import recent lists |
| Performance | SQLite actor and debounced edit saves avoid per-keystroke main-thread work |
| Logs/Audit | DB contains no image bytes or full OCR transcript; errors expose no event content |

## Fixtures

- Temporary owner-only directory and schema-version-1 SQLite database.
- Deterministic Vietnamese-English draft with field evidence and synthetic OCR
  sentinel.

## Commands

```text
xcodebuild -project SnapCal.xcodeproj -scheme SnapCal -destination 'platform=macOS' -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO -only-testing:SnapCalTests/SQLiteDraftStoreTests -only-testing:SnapCalTests/SnapCalModelTests test
```

## Acceptance Evidence

- `SQLiteDraftStoreTests` prove versioned typed round-trip across fresh store
  instances, owner-only storage, no screenshot/full-OCR sentinels, recent
  ordering, update, per-draft deletion, version-1 to version-2 migration, and
  rejection of unknown newer schemas.
- `SnapCalModelTests` prove extraction persistence, reopen into review,
  lifecycle update after confirmed Calendar success, explicit deletion, and
  graceful history unavailability with zero Calendar calls.
- The app builds with recent-draft lists in the main window and `MenuBarExtra`.
  Native inspection showed the Recent Drafts and Local History surfaces.
