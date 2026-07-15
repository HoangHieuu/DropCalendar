# Validation

## Proof Strategy

Prove provider negotiation independently from OCR, then prove both URL and
in-memory selections reach the existing editable review with zero Calendar
writes. Reuse validator tests for byte limits and decode failures, and compile
the macOS app against the deployed platform SDK.

## Test Plan

| Layer | Cases |
| --- | --- |
| Unit | Select first supported URL; load PNG/JPEG/HEIC data; convert TIFF; reject empty and unsupported providers; count ignored items |
| Integration | In-memory notch payload uses validator/extractor and reaches mandatory review with zero Calendar calls |
| E2E | Manually drag a fresh macOS floating screenshot thumbnail and the saved screenshot file into the notch |
| Platform | Targeted XCTest execution and unsigned macOS app build |
| Performance | Load only the first supported item; enforce the existing 20 MB maximum before OCR |
| Logs/Audit | No image-data logging or app-owned temporary file; no Calendar call before explicit review confirmation |

## Fixtures

- Deterministic in-memory PNG and TIFF bitmap data.
- Local PNG URL and unsupported text provider.
- Stub validator, OCR, extractor, and Calendar scheduler.

## Commands

```text
xcodebuild -project SnapCal.xcodeproj -scheme SnapCal -destination 'platform=macOS' -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO -only-testing:SnapCalTests/NotchDropZoneTests -only-testing:SnapCalTests/SnapCalModelTests test
xcodebuild -project SnapCal.xcodeproj -scheme SnapCal -destination 'platform=macOS' -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO build
```

## Acceptance Evidence

- `NotchDropZoneTests` prove raw image-data selection, ignored-item counting,
  unsupported-provider rejection, TIFF-to-PNG conversion, and immediate reads
  from both file-URL and temporary-file representations before their source
  URLs expire.
- `SnapCalModelTests` prove file and in-memory notch selections reach mandatory
  editable review with zero Calendar writes.
- The complete `SnapCalTests` suite passed on macOS. One team-signed Keychain
  round-trip test was skipped by its existing signing precondition.
- The unsigned macOS `SnapCal` scheme build succeeded.
- Direct floating screenshot thumbnail drag remains a manual E2E smoke check,
  so Harness E2E proof stays false until that interaction is observed.
