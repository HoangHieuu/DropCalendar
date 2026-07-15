# Exec Plan

## Goal

Add a native Account & Billing surface and make Accuracy entitlement-aware,
fast, bounded, and recoverable without changing Local Only.

## Scope

In scope:

- Google identity consent and SnapCal device sessions.
- Settings account/billing states and hosted URL actions.
- `/v2/me` UI cache and launch warm-up.
- Concurrent OCR/preprocessing/local-candidate/cloud work.
- 2048-pixel, 0.82-quality, 4 MiB multipart image upload.
- Installation retry key and device-only sealed-envelope recovery.

Out of scope:

- Automatic Calendar creation or batch confirmation.
- Requiring an account for Local Only.

## Risk Classification

Risk flags: auth, privacy, external systems, public contracts, macOS Keychain,
and existing behavior.

Hard gates: credential storage, cloud disclosure, and Calendar confirmation.

## Work Phases

1. Add provider-neutral account/session contracts.
2. Add production API client and Keychain records.
3. Add entitlement-aware model states and settings UI.
4. Optimize image/OCR task graph.
5. Add unit and macOS regression proof.

## Stop Conditions

Pause if Local Only makes a network/account call, checkout redirect enables
Accuracy, secrets move outside Keychain, or confirmation boundaries change.

