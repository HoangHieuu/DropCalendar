# 0010 Google Desktop OAuth And Calendar Boundary

Date: 2026-07-13

## Status

Accepted

## Context

US-002 introduces authentication, a persisted refresh token, network access,
and an irreversible Google Calendar write. A macOS desktop app cannot keep a
client secret confidential, and SnapCal must preserve the invariant that no
event is created before the user reviews the draft and explicitly confirms the
write.

## Decision

- Use Google's OAuth 2.0 authorization-code flow for desktop apps with PKCE,
  the system browser, a random state value, and an ephemeral `127.0.0.1`
  loopback callback.
- Embed only the public Desktop OAuth client ID. Do not copy the downloaded
  credential JSON or its client secret into the repository or app bundle.
- Request only
  `https://www.googleapis.com/auth/calendar.events.owned`.
- Store the refresh token in macOS Keychain with device-only accessibility.
  Keep access tokens and their expiry in memory only.
- Put Google REST payloads behind inward-facing authorization and calendar
  interfaces. Domain and SwiftUI types do not depend on Google SDK types.
- Require a review-state confirmation dialog before the application layer can
  transition to `creating` and call `events.insert`.
- Add App Sandbox client networking for Google HTTPS calls and server
  networking only for the short-lived loopback OAuth callback.

## Alternatives Considered

1. Embed and rely on the downloaded client secret. Rejected because installed
   apps are public clients and cannot protect it.
2. Use a service account. Rejected because personal Calendar access requires
   user authorization; domain-wide delegation is unrelated and over-privileged.
3. Use an embedded web view. Rejected because Google requires a secure external
   user agent for native OAuth.
4. Add a third-party auth/calendar SDK. Deferred because the bounded REST and
   PKCE surface is small, avoids supply-chain expansion, and remains testable
   through local protocols.

## Consequences

Positive:

- The user grants a narrow permission in Google's own browser surface.
- Long-lived authorization is protected by Keychain and can be disconnected.
- Provider calls and confirmation order are independently testable.

Tradeoffs:

- The app needs temporary localhost listener permission.
- Google testing-mode refresh tokens may expire and require reauthorization.
- Live OAuth and calendar writes still require user interaction and cannot be
  fully automated in unit tests.

## Follow-Up

- Decision 0013 refines token-exchange ownership after live proof showed that
  the installed Google OAuth credential rejects secretless exchange. The app
  remains secret-free; the local service owns the secret-bearing provider call.
- Add account identity and calendar selection only when a separate story needs
  the additional scopes.
- Revisit a vetted SDK if provider requirements outgrow the bounded adapter.
