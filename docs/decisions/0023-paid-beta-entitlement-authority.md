# 0023 Paid Beta Entitlement Authority

Date: 2026-07-15

## Status

Accepted

## Context

SnapCal needs a paid Accuracy tier without making Local Only account-dependent
or trusting stale client state, browser redirects, or a billing-provider lookup
on each extraction request.

## Decision

- Local Only remains anonymous, unlimited, free, and on-device.
- Pro Beta is US$4.99 per monthly period for 100 successful Accuracy screenshot
  extractions, limited initially to 50 invited accounts.
- Google identity creates a provider-neutral SnapCal user and rotating device
  session. Calendar authorization remains a separate client capability.
- Paddle-hosted checkout and customer portal own payment UI.
- Only a valid, deduplicated, ordered Paddle webhook may update the lean local
  subscription cache. Browser redirects and cached `/me` state never grant
  access.
- `trialing`, `active`, and `past_due` are entitled; `past_due` is warned.
  Paused and effective canceled states are not entitled. Scheduled cancellation
  retains access until the effective period end.
- Plan price, quota, limits, and feature flags remain server-configured.

## Alternatives Considered

1. Trust checkout completion in the app. Rejected because the redirect is not
   proof that the subscription is active.
2. Query Paddle on every Accuracy request. Rejected for hot-path latency,
   availability, cost, and coupling.
3. Require sign-in for Local Only. Rejected because it violates the free
   offline privacy boundary.

## Consequences

Positive:

- Access decisions remain fast, auditable, and independent of Paddle uptime.
- The user, plan, and entitlement contract can support future native clients.

Tradeoffs:

- Webhook ordering, retries, and reconciliation require explicit operations.
- Live checkout cannot launch until Paddle sandbox evidence is complete.

## Follow-Up

- Recalculate quota and provider ceilings after 500 successful beta calls.

