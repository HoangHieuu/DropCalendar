# Exec Plan

## Goal

Complete Phase 4 trust hardening without broadening Calendar permission or
silently retaining private screenshots.

## Scope

In scope:

- Reminder suggestion, editing, validation, and provider mapping.
- Local duplicate warnings and confirmation override.
- Online normalization and explicit MapKit candidate search.
- Default-off encrypted screenshot history and local-history deletion controls.

Out of scope:

- Calendar-read duplicate checks, automatic place search, and learned defaults.

## Risk Classification

Risk flags:

- Data model and deletion.
- Audit/security and private image retention.
- External MapKit and Google Calendar payload behavior.
- Existing review and persistence behavior.
- Multiple trust domains.

Hard gates:

- External provider behavior, private data retention, and data deletion.

## Work Phases

1. Lock decision 0018 and provider constraints.
2. Add pure reminder/duplicate/location policies.
3. Extend persistence and Calendar mapping.
4. Add encrypted vault and privacy settings.
5. Add review/settings UI.
6. Run focused, full, benchmark, and native UI proof.
7. Update Harness evidence.

## Stop Conditions

Pause if implementation would require Calendar read permission, automatic
location disclosure, plaintext screenshot storage, or deletion of a user-owned
source file.
