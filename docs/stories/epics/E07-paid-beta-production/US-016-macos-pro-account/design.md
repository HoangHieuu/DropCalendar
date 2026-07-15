# Design

## Domain Model

`AccountSnapshot` separates identity, entitlement, plan, quota, billing period,
and payment warning. Calendar authorization remains a separate capability.

## Application Flow

The app warms `/v2/me` only when a SnapCal session exists. Choosing Accuracy
checks visible entitlement, but reservation remains server-authoritative. OCR
and image preprocessing run off the main actor; local candidates and the cloud
request overlap after OCR.

## Interface Contract

A lightweight client owns auth, `/me`, plans, checkout, portal, multipart
extraction, and retry recovery. Stable API codes map into user-facing states.

## Data Model

SnapCal refresh tokens and the Curve25519 private retry key live in Keychain.
Google refresh tokens also remain Keychain-only. Production Calendar refreshes
use the authenticated SnapCal API broker rather than the development loopback
helper. Only a 15-minute `/me` UI snapshot may be cached locally.

## UI / Platform Impact

Use a flat macOS Settings `TabView` with `Form` sections. Keep async state in
the shared model/service, use lifecycle-bound tasks, and expose simple row
states to the view.

## Observability

Client logs include only request IDs, stage names, and redacted error codes.

## Alternatives Considered

1. Web account dashboard only: rejected because quota and disconnect state
   belong in the native workflow.
2. Entitlement embedded in app constants: rejected because plans must change
   without an app release.
