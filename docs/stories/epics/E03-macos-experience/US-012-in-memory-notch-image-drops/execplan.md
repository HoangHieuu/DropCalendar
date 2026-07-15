# Exec Plan

## Goal

Make the macOS notch interoperable with floating screenshot thumbnails and
image-data drag providers while preserving SnapCal's review, retention, and
Calendar-write boundaries.

## Scope

In scope:

- Accept local file URLs and PNG, JPEG, HEIC, or TIFF drag representations.
- Convert TIFF representations to PNG in memory, matching clipboard behavior.
- Read temporary representations before the provider invalidates their URL.
- Reuse the existing 20 MB/decode validation and extraction path.
- Prove that a successful import reaches review without a Calendar write.

Out of scope:

- New retained-image behavior or schema changes.
- Remote downloads and arbitrary file promises.
- Extraction-quality or provider changes.

## Risk Classification

Risk flags:

- Audit/security and private image handling.
- Existing drag-and-drop behavior.
- Weak direct automation for the macOS floating screenshot UI.

Hard gates:

- No implicit Calendar write.
- No new app-owned temporary or retained screenshot file.
- Unsupported, empty, corrupt, or oversized data fails before OCR.

## Work Phases

1. Lock the temporary-representation and retention boundary.
2. Add a typed drop payload and provider loader.
3. Route file and in-memory payloads through the shared application model.
4. Add provider-selection and review-boundary tests.
5. Run targeted tests and a full macOS build.
6. Update Harness evidence and record a detailed trace.

## Stop Conditions

Pause for human confirmation if support requires persisting a temporary image,
weakening validation, sending Local Only data to a provider, or creating a
Calendar event before review and confirmation.

