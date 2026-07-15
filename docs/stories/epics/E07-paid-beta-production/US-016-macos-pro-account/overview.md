# Overview

## Current Behavior

Accuracy is an unmetered mode backed by the loopback helper. Settings contains
privacy controls only, and Google OAuth starts only when creating a Calendar
event.

## Target Behavior

Local Only remains unchanged. Remote production Accuracy reflects SnapCal
identity, invitation, subscription, quota, payment warning, and recoverable
session state. The user can subscribe, manage billing, refresh entitlement,
sign out of SnapCal, or independently disconnect Calendar.

## Affected Users

- Anonymous Local Only users.
- Invited Free, Pro, past-due, exhausted, paused, and canceled users.

## Affected Product Docs

- `docs/product/billing-release.md`
- `docs/product/extraction.md`
- `docs/product/review-calendar.md`

## Non-Goals

- Forced reauthorization for existing Calendar users.
- Account requirement for Local Only.
