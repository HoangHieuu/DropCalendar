# US-002 Overview

## Current Behavior

SnapCal produces an editable in-memory event draft. The Create Event control is
disabled and the app has no authentication, Keychain, network, or calendar
provider implementation.

## Target Behavior

From a complete review, the user requests creation, inspects a final confirmation
dialog, and explicitly confirms. SnapCal then obtains a Google access token
through desktop OAuth or a Keychain refresh token, inserts one event into the
user's primary Google Calendar, and reports a calendar link or a recoverable
error. Cancellation and failures preserve the draft.

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
