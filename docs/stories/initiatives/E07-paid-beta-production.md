# E07 Paid Beta And Production Release

## Goal

Move SnapCal from a local prototype into a 50-user paid macOS beta without
weakening Local Only privacy or the explicit per-event Calendar confirmation
boundary.

## Locked Product Rules

- Local Only remains anonymous, unlimited, on-device, and free.
- Pro Beta costs US$4.99 per month and includes 100 successful Accuracy
  screenshot extractions per billing period.
- One accepted screenshot consumes one unit regardless of how many event
  drafts it yields. Failures and visible Local Only fallbacks consume none.
- Paddle webhooks, not browser redirects, own subscription entitlement.
- Accuracy requires a SnapCal session backed by Google identity and an invited
  beta account.
- Calendar writes remain direct from the app and require a separate explicit
  confirmation for every event.
- The service stores no screenshot, OCR text, prompt, plaintext event result,
  Google credential, or OpenRouter credential.

## Stories

1. `US-014-production-api-and-usage` — production configuration, PostgreSQL
   schema, sessions, quota reservation/finalization, `/v2` extraction, and
   encrypted retry envelopes.
2. `US-015-paddle-entitlements` — invited beta access, hosted checkout and
   portal links, signed webhook ingestion, and local entitlement cache.
3. `US-016-macos-pro-account` — Google identity sign-in, account and billing
   settings, entitlement-aware Accuracy UI, optimized multipart upload, and
   encrypted retry keys.
4. `US-017-production-delivery` — container, Terraform, CI/CD, migration,
   Developer ID/notarization, update, observability, and rollout runbooks.

## Validation Shape

- Unit and integration tests cover session rotation, webhook ordering,
  reservation concurrency, idempotency, rate limits, privacy redaction, and
  client entitlement state.
- Existing Local Only, draft, review, and Calendar confirmation regression
  suites remain mandatory.
- Provider-fake load checks precede a bounded 20-request live cost calibration.
- Cloud, billing, OAuth verification, signing, and domain proof remain explicit
  operator gates when account credentials are unavailable.

## Exit Criteria

- Staging is reproducibly deployable from an immutable image and migration.
- A signed beta client can authenticate, subscribe, run Accuracy within quota,
  recover its encrypted result for 15 minutes, and confirm events one at a
  time.
- Local Only performs zero account, billing, backend, or model-provider calls.
- A five-user internal wave completes without a privacy, billing, quota, or
  Calendar-confirmation defect.

