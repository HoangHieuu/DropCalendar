# Validation

## Proof Strategy

Prove that the koi-pond mark compiles, appears in every existing mark caller,
preserves accessibility and motion boundaries, and does not alter extraction,
review, persistence, privacy, notch, or Calendar behavior.

## Test Plan

| Layer | Cases |
| --- | --- |
| Unit | Existing model and notch safety tests remain green |
| Integration | Existing import/review flow remains unchanged |
| E2E | Existing import-mode and clipboard-to-review UI flows remain green |
| Platform | Build and full macOS UI smoke; inspect default and full-screen mark |
| Performance | Static vector/canvas mark adds no image/network dependency |
| Logs/Audit | No screenshot/OCR/event content enters logs or traces |

## Fixtures

- Existing macOS UI-test storage and `en-051.png` fixture.
- Supplied `ref.jpg` used only as local visual direction.

## Commands

```text
xcodebuild -project SnapCal.xcodeproj -scheme SnapCal -destination 'platform=macOS' -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO build
xcodebuild -quiet -project SnapCal.xcodeproj -scheme SnapCal -destination 'platform=macOS' -derivedDataPath .build/DerivedDataFocused CODE_SIGNING_ALLOWED=NO test -only-testing:SnapCalTests/NotchDropZoneTests -only-testing:SnapCalTests/SnapCalModelTests
scripts/run-ui-smoke.sh
```

## Acceptance Evidence

Pending implementation and fresh proof.
