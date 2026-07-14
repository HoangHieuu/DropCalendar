# Validation

## Proof Strategy

Prove reminder policy boundaries and provider JSON, duplicate false-positive
softness and explicit override, zero automatic map calls, encrypted-vault
round-trip/default-off behavior, Keychain-backed key deletion, and Clear All
scope.

## Test Plan

| Layer | Cases |
| --- | --- |
| Unit | reminder timing/limits; fingerprint and composite duplicates; online normalization |
| Integration | Calendar JSON overrides; SQLite duplicate lookup; encrypted vault and history deletion |
| E2E | import twice, inspect warning, confirm override; configure reminders; select place candidate |
| Platform | menu bar/settings/review UI; MapKit unavailable state; Keychain test fixture |
| Performance | SHA-256 and duplicate scan are bounded; vault and SQLite work off main actor |
| Logs/Audit | no raw screenshot/OCR/location text/key in logs or plaintext files |

## Fixtures

- Deterministic future/same-day/online/all-day event drafts.
- Duplicate history rows with exact fingerprint and composite matches.
- Temporary encrypted vault with in-memory test key store.
- Stub location resolver with multiple candidates.

## Commands

```text
xcodebuild -project SnapCal.xcodeproj -scheme SnapCal -destination 'platform=macOS' -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO -only-testing:SnapCalTests/ReminderPolicyTests -only-testing:SnapCalTests/DuplicateDetectorTests -only-testing:SnapCalTests/ScreenshotVaultTests -only-testing:SnapCalTests/SnapCalModelTests test
```

## Acceptance Evidence

- `ReminderPolicyTests` and `CalendarEventMapperTests` prove contextual
  suggestions, past-trigger removal, all-day behavior, provider ranges, and the
  five-override boundary. `GoogleCalendarClientTests` prove reviewed overrides
  in the provider JSON.
- `DuplicateDetectorTests`, `SQLiteDraftStoreTests`, and `SnapCalModelTests`
  prove exact-fingerprint/high-confidence signals, composite and soft warnings,
  local-only lookup, override through the normal confirmation state, and zero
  Calendar calls before confirmation.
- `SnapCalModelTests` prove location resolution is never automatic, an explicit
  candidate request can return multiple choices, and user selection edits the
  draft while failure preserves the original text.
- `ScreenshotVaultTests` prove AES-GCM round-trip, no plaintext sentinel,
  owner-only files, opt-in persistence, per-draft deletion, Clear All, and key
  deletion. Model tests prove default-off behavior never touches the vault and
  Clear All never calls Calendar.
- Native inspection on 2026-07-14 showed the Local Only cloud disclosure and
  default-off encrypted screenshot setting. Live Apple Maps lookup remains a
  manual platform check because it transmits the entered query only after a
  user action.
