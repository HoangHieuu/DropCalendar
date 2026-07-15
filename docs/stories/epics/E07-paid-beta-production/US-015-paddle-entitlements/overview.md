# Overview

## Current Behavior

SnapCal has no account plan, checkout, subscription, or billing portal.

## Target Behavior

Invited signed-in users can open Paddle-hosted checkout and portal sessions.
Signed webhooks maintain the lean local subscription cache. `trialing`,
`active`, and `past_due` remain entitled; `paused` and effective cancellation
do not.

## Affected Users

- Invited Free and Pro Beta users.
- Operators reviewing webhook failures.

## Affected Product Docs

- `docs/product/billing-release.md`
- `docs/product/privacy-quality.md`

## Non-Goals

- Custom card forms, tax logic, invoice storage, or payment retries.
