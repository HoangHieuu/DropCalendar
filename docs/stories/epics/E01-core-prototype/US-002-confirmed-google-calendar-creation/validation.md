# US-002 Validation

## Proof Strategy

Prove the irreversible write boundary with a scheduler spy before exercising
provider code. Separately prove PKCE/state parsing, Keychain abstraction,
timed/all-day payload mapping, strict response parsing, and recoverable HTTP
errors. Build and launch prove the macOS entitlements and platform wiring. Live
OAuth/create remains a user-confirmed platform check.

## Test Plan

| Layer | Cases |
| --- | --- |
| Unit | PKCE shape; callback state/cancel/error; title/start/end validation; timed and all-day payloads; provider response parsing |
| Integration | request does not call scheduler; cancel does not call; confirm calls once; failure preserves draft; retry requires confirmation; disconnect clears state |
| E2E | User-driven browser consent and one confirmed primary-calendar event |
| Platform | Xcode build/test; app launch; browser open; loopback callback; Keychain entitlement behavior |
| Performance | No benchmark; provider call remains outside render paths |
| Logs/Audit | Static scan and tests confirm tokens, codes, secret, and event payloads are not logged |

## Fixtures

- In-memory credential store for the OAuth refresh path.
- Scheduler spy and deterministic success/failure receipts.
- OAuth callback URLs for valid, mismatched-state, denied, and malformed cases.
- Timed and all-day drafts with a fixed `Asia/Ho_Chi_Minh` calendar.
- Calendar success, 401, and 429 response bodies.

## Commands

```bash
xcodebuild -project SnapCal.xcodeproj -scheme SnapCal \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test
```

## Acceptance Evidence

- 2026-07-13: `xcodebuild -project SnapCal.xcodeproj -scheme SnapCal
  -destination 'platform=macOS' -derivedDataPath .build/DerivedData
  CODE_SIGNING_ALLOWED=NO test` succeeded.
- 2026-07-13: a normal local-sign build succeeded with the app sandbox,
  user-selected read-only files, outgoing network, and localhost listener
  entitlements embedded.
- 22 tests passed across image validation, local extraction, confirmation-state
  enforcement, OAuth callback/PKCE validation, Calendar mapping, and Calendar
  adapter success/error handling.
- Static scan found the public OAuth client ID only; no downloaded JSON, client
  secret, refresh token, access token, authorization code, or private event
  payload is bundled or logged.
- Pending user-driven proof: Google consent, loopback callback, Keychain reuse,
  one explicitly confirmed event, provider link, and disconnect/reconnect.
