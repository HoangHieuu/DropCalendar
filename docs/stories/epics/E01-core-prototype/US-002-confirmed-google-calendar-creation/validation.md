# US-002 Validation

## Proof Strategy

Prove the irreversible write boundary with a scheduler spy before exercising
provider code. Separately prove PKCE/state parsing, Keychain abstraction,
timed/all-day payload mapping, strict response parsing, and recoverable HTTP
errors. Build and launch prove the macOS entitlements and platform wiring. Live
OAuth/create remains a user-confirmed platform check.
Keychain policy tests prove signature selection and alternate-store behavior;
an isolated platform round trip proves the ad-hoc login-Keychain path without
reading or writing a real Google token.

## Test Plan

| Layer | Cases |
| --- | --- |
| Unit | PKCE shape; callback state/cancel/error; signature-aware Keychain policy; alternate-store reads; title/start/end validation; timed and all-day payloads; token-broker grant validation; provider response parsing |
| Integration | request does not call scheduler; cancel does not call; confirm calls once; stored refresh token avoids interactive authorization; failure preserves draft; retry requires confirmation; disconnect clears both stores |
| E2E | User-driven browser consent and one confirmed primary-calendar event |
| Platform | Xcode build/test; isolated ad-hoc login-Keychain round trip and cleanup; app launch; browser open; loopback callback; local token-broker smoke; signed Data Protection Keychain behavior |
| Performance | No benchmark; provider call remains outside render paths |
| Logs/Audit | Static scan and tests confirm tokens, codes, secret, and event payloads are not logged |

## Fixtures

- In-memory credential store for the OAuth refresh path.
- In-memory dual-backend Keychain client and an isolated platform service name.
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
- 2026-07-14: macOS unified logs proved browser callback success followed by
  HTTP 400 from `oauth2.googleapis.com/token`; no Calendar endpoint was called.
- 2026-07-14: the configured loopback broker loaded the external installed-app
  credential, reached Google's token endpoint with an intentionally invalid
  code, and returned only redacted `oauth_exchange_rejected` with HTTP 400.
- 2026-07-14: all 32 Xcode tests and all 16 FastAPI contract tests passed,
  including broker validation, client mismatch, response redaction, secret
  confinement, and non-fatal refresh-token persistence failure.
- 2026-07-14: all 41 Xcode tests and all 16 FastAPI contract tests passed after
  adding signature-aware storage. An isolated platform test round-tripped and
  deleted a non-provider fixture through the ad-hoc login-Keychain backend;
  deterministic tests cover team-signed selection, alternate-store reads, and
  stale-copy cleanup without exposing credential values.
- 2026-07-14: the user reported a successful live extraction-to-Calendar run:
  they reviewed the extracted image information, explicitly confirmed creation,
  and observed the event in Google Calendar. This closes the Phase 1 live OAuth
  and confirmed-write proof without exposing event contents or credentials.
- Pending user-driven proof: relaunch refresh-token reuse, provider-link opening,
  signed Data Protection Keychain reuse, and disconnect/reconnect.
