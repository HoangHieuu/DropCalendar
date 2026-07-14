# US-002 Exec Plan

## Goal

Create exactly one reviewed event in the user's primary Google Calendar after
explicit confirmation, with safe OAuth token ownership and recoverable failure.

## Scope

In scope:

- Desktop OAuth authorization code flow with PKCE and loopback callback.
- Keychain refresh-token storage and disconnect.
- Google Calendar `events.insert` adapter.
- Timed and all-day event mapping with an editable end.
- Confirmation, progress, success, cancellation, retry, and error UI.
- Unit, integration-spy, provider-contract, build, and launch proof.

Out of scope:

- Calendar list reads, account profile scopes, duplicate detection, reminders,
  draft persistence, mobile, and production OAuth verification.

## Risk Classification

Risk flags:

- Auth.
- Audit/security.
- External systems.
- Public contracts.
- Existing behavior.
- Weak proof.

Hard gates:

- Authentication and external provider behavior.

## Work Phases

1. Lock OAuth, token, scope, confirmation, and provider boundaries.
2. Add domain mapping and application state machine.
3. Add PKCE, loopback, token, Keychain, and Calendar REST infrastructure.
4. Add review UI states without moving provider work into views.
5. Add deterministic tests and build/launch proof.
6. Perform live OAuth/calendar proof only through explicit user interaction.
7. Update product truth, decision, story proof, and Harness trace.
8. Route token exchange through the secret-owning loopback service after live
   proof shows the installed credential rejects secretless exchange.

## Stop Conditions

Pause for human confirmation if:

- Google requires a broader scope than `calendar.events.owned`.
- Live proof would create an event without the user's visible confirmation.
- Credential material beyond the public client ID would need to enter source.
- Validation would need to bypass state, PKCE, or provider response checks.
