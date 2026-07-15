# Account, Billing, Quota, And Release

## Plans

Local Only is anonymous, unlimited, and entirely on-device. It must work with
no account, subscription, backend, database, or provider availability.

Pro Beta costs US$4.99 per monthly billing period and grants 100 successful
Accuracy screenshot imports. One screenshot consumes one unit even when the
result contains several events. Failed, rejected, timed-out, invalid, or local
fallback requests consume no unit. There is no trial, overage, credit pack,
rollover, or batch-image discount.

The server owns price copy, quota, rate limits, and feature flags. The app
reads them from `/v2/plans` and `/v2/me`; it does not grant entitlement from a
browser redirect or locally cached account state.

## Identity And Entitlement

Google identity extends the installed-app PKCE loopback flow with `openid
email` through incremental consent. Calendar keeps its narrow
`calendar.events.owned` scope. Google refresh tokens remain only in macOS
Keychain. A configured production app exchanges them transiently through the
authenticated `/v2/auth/google/token` endpoint; the backend forwards them to
Google and never stores them. Development retains the `/v1` loopback broker.

Paddle is merchant of record. Signed, deduplicated Paddle webhooks own the
local subscription cache. `trialing`, `active`, and `past_due` are entitled
until the effective period end; `past_due` also exposes a payment warning.
`paused` and effective `canceled` subscriptions are not entitled. A scheduled
cancellation retains access until its effective timestamp.

Checkout requires authentication and an active beta invitation. Customer
portal URLs are short-lived and never cached. The first beta is capped at 50
invited accounts.

## Quota And Abuse Boundary

An Accuracy request has one reserve transaction and one finalize transaction.
The reserve transaction locks the user and usage period, checks invite,
entitlement, remaining quota, provider budget, idempotency, and limits, then
increments `reserved_units`. The finalize transaction releases the reservation
and either increments `consumed_units` for a valid non-empty response or leaves
consumption unchanged for failure.

Per user, the server permits at most two concurrent Accuracy requests, five
attempts in a rolling minute, and 30 attempts in a rolling day. Duplicate
idempotency keys never call the provider twice or consume twice. The server
uses Paddle's webhook cache and never queries Paddle or OpenRouter on the hot
entitlement path.

## Account UX

- Signed out: explain that Local Only stays free and offer Google sign-in.
- Signed-in Free: show Pro Beta price, 100-import benefit, disclosure, and
  Subscribe when invited.
- Active or trialing: show quota remaining and period end.
- Past due: retain Accuracy temporarily and show Manage Billing.
- Exhausted: disable Accuracy until reset while Local Only remains available.
- Paused or canceled: disable Accuracy and direct the user to Manage Billing.
- Always expose Restore/Refresh Purchase, Sign Out of SnapCal, and Disconnect
  Google Calendar.

Returning to SnapCal after checkout refreshes `/v2/me`; only the Paddle webhook
can change access. Every extracted event remains a local draft and still needs
its own Calendar confirmation.

## Distribution

SnapCal ships directly as a Developer ID-signed, hardened-runtime macOS app in
a signed and notarized DMG. Release tags run the locked Swift/Python checks,
archive with a monotonically increasing build number, notarize with
`notarytool`, staple and assess the DMG, sign the update with Sparkle EdDSA,
and publish immutable artifacts to GitHub Releases.

The owned domain exposes product, privacy, terms, download, API, staging API,
and Sparkle appcast endpoints. Sparkle is configured only in Release builds
with a real HTTPS feed and public key. Staging and production never share GCP,
Neon, Paddle, Google OAuth, or OpenRouter credentials.
