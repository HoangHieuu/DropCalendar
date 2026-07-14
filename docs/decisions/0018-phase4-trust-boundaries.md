# 0018 Phase 4 Trust Boundaries

Date: 2026-07-14

## Status

Accepted

## Context

Phase 4 adds reminder overrides, duplicate signals, place resolution, and
optional screenshot history. These features affect Calendar payloads, external
map search, private storage, and deletion.

## Decision

- Reminders are typed popup/email overrides. Suggestions are deterministic,
  remove reminders whose trigger is already past, and enforce Google's current
  limits of at most five overrides and 0...40320 minutes before start.
- Duplicate detection remains local-only. It compares a SHA-256 source
  fingerprint plus normalized title/start/location against recent SnapCal
  records. Warnings never block creation; the existing explicit confirmation
  dialog names the duplicate risk before an override.
- Venue/address resolution uses a replaceable MapKit adapter only after the user
  chooses Find Places. The UI discloses that the location text is sent to Apple
  Maps. No location query runs automatically and no device location permission
  is requested.
- Screenshot history defaults off. When explicitly enabled, SnapCal encrypts
  retained image bytes with AES-GCM using a random key held in the macOS
  Keychain. Files and their directory are owner-only. Disabling history stops
  future retention; explicit per-draft or Clear All deletion removes encrypted
  files. Clear All also removes the vault key.
- SnapCal never deletes the user's original Finder/Photos source file. “Delete
  raw screenshot” means SnapCal creates no retained copy by default and deletes
  only copies owned by its optional encrypted vault.

## Alternatives Considered

1. Read Google Calendar for duplicates. Rejected because the local signals are
   sufficient for MVP and broader read permission is not authorized.
2. Automatic place search. Rejected because it would disclose private venue
   text without an explicit user action.
3. Plaintext screenshot history. Rejected because private images require more
   protection than filesystem permissions alone.
4. Silently suppress duplicate creation. Rejected because warnings can be
   false positives and the user remains the authority.

## Consequences

- Reminder and duplicate behavior is deterministic and testable without
  providers.
- Place quality depends on MapKit network availability and user selection.
- Screenshot-history encryption adds a Keychain dependency, but default-off
  imports still retain no app-owned image file.

## Verification

```text
xcodebuild -project SnapCal.xcodeproj -scheme SnapCal -destination 'platform=macOS' -derivedDataPath .build/DerivedData -only-testing:SnapCalTests/ReminderPolicyTests -only-testing:SnapCalTests/DuplicateDetectorTests -only-testing:SnapCalTests/ScreenshotVaultTests -only-testing:SnapCalTests/SnapCalModelTests test
```
