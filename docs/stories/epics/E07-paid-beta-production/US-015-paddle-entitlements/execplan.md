# Exec Plan

## Goal

Make Paddle's signed subscription events the authority for Pro Beta access.

## Scope

In scope:

- Hosted checkout and portal URLs.
- Raw-body webhook signature verification and event deduplication.
- Ordered, idempotent subscription cache updates.
- Invite enforcement and entitlement mapping.

Out of scope:

- Granting access from browser redirects.
- Trials, annual plans, overages, credits, rollover, or App Store billing.

## Risk Classification

Risk flags: auth, authorization, data model, audit/security, payments, webhooks,
and public contracts.

Hard gates: billing authorization, signed external input, and entitlement
revocation.

## Work Phases

1. Lock subscription state rules.
2. Implement Paddle API adapter and webhook verifier.
3. Add checkout, portal, and webhook routes.
4. Add ordering, deduplication, and failure proof.
5. Record validation and Harness status.

## Stop Conditions

Pause if a redirect would grant access, a bad signature is accepted, an older
event can overwrite newer entitlement state, or billing secrets enter logs.

