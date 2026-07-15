# Validation

## Proof Strategy

Use recording clients and Keychain isolation to prove each account state and
zero-network Local Only behavior.

## Test Plan

| Layer | Cases |
| --- | --- |
| Unit | entitlement states, stage transitions, image/OCR bounds, token rotation |
| Integration | auth -> `/me` -> extraction -> quota refresh -> retry envelope |
| E2E | Settings actions and one-at-a-time multi-event confirmation |
| Platform | signed Keychain, system browser, relaunch, disconnect |
| Performance | Local Only no regression; upload <=4 MiB |
| Logs/Audit | no image/OCR/event/token/email leakage |

## Fixtures

Account snapshots for anonymous, Free, active, past-due, exhausted,
paused/canceled, plus success/failure extraction responses.

## Commands

```text
xcodebuild -project SnapCal.xcodeproj -scheme SnapCal -destination 'platform=macOS' -derivedDataPath .build/DerivedData test
```

## Acceptance Evidence

Implemented and covered by the macOS suite. A Developer ID-signed clean-machine
Keychain, browser, and update smoke remains a release gate.
