# 0013 Google OAuth Loopback Token Broker

Date: 2026-07-14

## Status

Accepted

## Context

US-002's first user-driven OAuth run completed browser consent and the loopback
callback, but Google returned HTTP 400 from the token endpoint. The configured
Desktop OAuth credential requires its generated client secret during token
exchange. Sending no secret makes the direct native exchange fail; embedding
the secret or downloaded credential JSON would violate SnapCal's credential
boundary and would not make a distributed desktop app confidential.

The repository already has a `127.0.0.1` FastAPI service for opt-in extraction.
It can own the provider-specific secret while the native app continues to own
PKCE, state validation, tokens, explicit confirmation, and Calendar insertion.

## Decision

- Route authorization-code and refresh-token exchanges through
  `POST /v1/google-oauth/token` on the loopback SnapCal service.
- Keep the downloaded installed-app credential JSON outside the repository and
  configure its absolute path through ignored
  `GOOGLE_OAUTH_CREDENTIALS_FILE` environment state.
- Validate the request grant shape, client ID, PKCE verifier, and IPv4 loopback
  redirect before any provider call.
- Add the client secret only inside the local service's HTTPS request to
  Google's token endpoint. Never return, log, or copy it into the native app.
- Return only access-token lifetime and optional refresh-token fields. Redact
  Google response bodies and expose stable helper-unavailable, client-mismatch,
  and exchange-rejected categories.
- Cache a valid access token before attempting Keychain persistence. A local
  ad-hoc build may complete the explicitly confirmed event even if it cannot
  persist the refresh token; it must reconnect later instead of falsely
  reporting that the current Calendar write failed.

## Alternatives Considered

1. Embed the downloaded client secret. Rejected because credentials must not
   enter source or the app bundle.
2. Make the native app read the downloaded JSON or a secret environment
   variable. Rejected because it moves the same secret into the app process and
   breaks the accepted boundary.
3. Replace REST OAuth with Google Sign-In for iOS/macOS. Deferred because it
   requires a new iOS-type OAuth client, Apple certificate signing, Keychain
   access-group configuration, and an SDK dependency.
4. Open a prefilled Google Calendar template URL. Rejected because it no longer
   proves `events.insert` or returns a provider receipt.

## Consequences

Positive:

- The existing installed OAuth credential can complete exchange without
  exposing its secret in the app or repository.
- Provider errors are diagnosable without leaking codes, tokens, secrets, or
  response bodies.
- Explicit confirmation and the one-write application boundary remain intact.

Tradeoffs:

- Calendar OAuth now requires the local SnapCal service even in Local Only
  extraction mode.
- The app sends OAuth codes and refresh tokens over host-only HTTP to a fixed
  local service port; production distribution should replace this development
  boundary with a signed native SDK flow or authenticated production broker.
- Ad-hoc local builds cannot reliably persist data-protection Keychain items
  and may require Google consent again after restart.

## Follow-Up

- Before production distribution, choose between an Apple-signed Google
  Sign-In SDK integration and an authenticated hosted broker.
- Add signed Keychain platform proof once an Apple signing identity is present.
