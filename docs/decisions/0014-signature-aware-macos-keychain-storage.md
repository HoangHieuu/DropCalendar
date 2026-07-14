# 0014 Signature-Aware macOS Keychain Storage

Date: 2026-07-14

## Status

Accepted

## Context

SnapCal persists only the Google OAuth refresh token. The original implementation
always requested the macOS Data Protection Keychain. Live inspection showed the
current Xcode artifact is ad-hoc signed, has no team identifier, and has no
persisted SnapCal item. That build can use an in-memory access token for the
current launch, but it cannot reliably reuse authorization after restart.

Apple recommends the Data Protection Keychain for signed applications. macOS
also provides the user's encrypted login Keychain for legacy macOS keychain
items. The production storage choice must remain stronger without making local
development request Google consent for every app launch.

## Decision

- Inspect the running app's code signature without invoking an external process.
- Use the Data Protection Keychain when the signature has an Apple team
  identifier.
- Use the user's local login Keychain when the build is ad-hoc and has no team
  identifier.
- Keep the same stable service and OAuth-client account identifiers in both
  stores. Do not synchronize either item through iCloud.
- Read the preferred store first and the alternate store second so authorization
  survives a transition from a local build to a signed build.
- Save only to the preferred store and remove a stale alternate copy after a
  successful save.
- Disconnect removes the refresh token from both stores. Access tokens remain
  memory-only.
- Never print, log, trace, or expose token contents. Platform tests use isolated
  fake values and delete them after the round trip.

## Alternatives Considered

1. Require an Apple Developer signing identity before any local testing.
   Rejected because it blocks development and does not improve the security of
   a local-only test token stored in the user's encrypted login Keychain.
2. Always use the login Keychain. Rejected because signed production builds can
   use Apple's recommended Data Protection Keychain.
3. Store the refresh token in `UserDefaults`, a file, or `.env`. Rejected because
   those are not credential stores.
4. Ignore persistence failures. Rejected because it produces repeated browser
   consent with no actionable explanation.

## Consequences

Positive:

- Ad-hoc Xcode builds can reuse Google authorization across app launches.
- Signed builds retain Data Protection Keychain behavior.
- A later signing transition does not strand an existing local authorization.

Tradeoffs:

- The ad-hoc development item uses macOS login-Keychain access controls rather
  than iOS-style Data Protection Keychain semantics.
- Google testing-mode refresh-token expiry can still require reauthorization.
- Production distribution still requires a stable Apple signing identity and a
  production replacement for the localhost token broker.

## Follow-Up

- 2026-07-14: the default macOS target moved from forced ad-hoc signing to
  automatic Apple Development signing for team `HKUD5AT6V6`. The registered
  identifier is `com.hkud5at6v6.snapcal`, and its provisioned Keychain access
  group is `HKUD5AT6V6.com.hkud5at6v6.snapcal`.
- An isolated signed-host platform test now proves a Data Protection Keychain
  write, read, delete, and not-found round trip without using a provider token.
- The obsolete login-Keychain OAuth item was deleted during the transition. The
  signed app then launched and relaunched without a Keychain password dialog.
- User-driven proof still needs one new Google consent followed by refresh-token
  reuse after relaunch and Disconnect/reconnect verification.
- Production distribution still needs distribution signing/notarization and a
  production OAuth broker or Google Sign-In boundary.
