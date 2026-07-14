# US-002 Overview

## Current Behavior

SnapCal produces an editable in-memory event draft and has guarded OAuth,
Keychain, Calendar REST, and confirmation-state implementations. The first live
run completed consent and callback but exposed a provider mismatch: the
installed OAuth credential rejected the app's secretless token exchange. Token
exchange now uses the configured loopback SnapCal service, while the app keeps
PKCE/state validation, tokens, and Calendar insertion.
The default local build is Apple Development signed for team `HKUD5AT6V6` with
a registered application identifier and Keychain access group, so it uses Data
Protection Keychain. Deliberately ad-hoc builds retain the login-Keychain
fallback.

## Target Behavior

From a complete review, the user requests creation, inspects a final confirmation
dialog, and explicitly confirms. SnapCal then obtains a Google access token
through desktop OAuth or a Keychain refresh token, inserts one event into the
user's primary Google Calendar, and reports a calendar link or a recoverable
error. Cancellation and failures preserve the draft.
Authorization persists across launches: signed builds prefer Data Protection
Keychain and ad-hoc development builds use the local login Keychain.

## Affected Users

- A macOS user creating an event in a Google Calendar they own.

## Affected Product Docs

- `docs/product/review-calendar.md`
- `docs/product/privacy-quality.md`
- `docs/ARCHITECTURE.md`
- `docs/TEST_MATRIX.md`

## Non-Goals

- Calendar selection or reading the user's complete calendar list.
- Duplicate detection or broad calendar-history access.
- Background or automatic event creation.
- OAuth verification, production distribution, or mobile authentication.
- Storing drafts, screenshots, access tokens, or private event payloads.
