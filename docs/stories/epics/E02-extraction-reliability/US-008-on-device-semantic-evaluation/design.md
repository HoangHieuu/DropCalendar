# US-008 Design

## Domain Model

The user-visible extraction modes are `localSemantic` and `accuracy`.
`localSemantic` is one privacy choice backed by either the Apple on-device
language model or the deterministic local fallback. Extraction provenance is a
separate value and never changes the selected mode. Model proposals never
bypass deterministic validation or mandatory review.

## Application Flow

1. Run Apple Vision OCR locally.
2. Produce the current deterministic candidate as the safety baseline.
3. Check compile-time SDK support, macOS availability, locale support, model
   readiness.
4. When eligible, ask `SystemLanguageModel.default` for one to ten guided,
   evidence-bearing proposals over bounded OCR text.
5. Reject proposal fields whose evidence is absent from OCR, validate critical
   temporal values deterministically, and reconcile disagreement with the
   baseline.
6. On any unavailable, unsupported, invalid, or failed semantic path, return the
   deterministic candidate and record a visible fallback reason.
7. Require a separate explicit action before any cloud Accuracy Mode request.

## Interface Contract

`LocalSemanticEventExtracting` is an async inward-facing protocol. Its result is
typed, evidence-validated drafts plus a model identifier. Unavailable and failed
paths throw bounded non-sensitive errors that the application converts into
fallback provenance. The unavailable implementation performs no network
operation. The app-facing mode enum contains only Local Semantic and Accuracy.

## Data Model

No SQL schema migration is required. The persisted payload gains semantic-model
and deterministic-fallback provenance while continuing to decode the earlier
local, local-fallback, and OpenRouter values. Reopened drafts must retain
truthful source disclosure.

## UI / Platform Impact

The picker always offers Local Semantic. Import copy explains that it uses the
Apple on-device model when available and deterministic rules otherwise. Review
copy states which engine produced that draft. A fallback never changes the mode
selection or steers the user into cloud processing.

## Observability

The capability command reports only architecture, OS version, Xcode version,
SDK version, module availability, and bounded availability/fallback categories.
Application logs must not contain OCR, prompt text, generated event fields, or
model transcripts.

## Alternatives Considered

1. Three visible modes. Rejected by decision 0026 as unnecessary implementation
   detail.
2. Silent deterministic fallback. Rejected because source disclosure is a
   product trust requirement.
3. Automatic Accuracy fallback. Rejected because it would change the privacy
   choice without consent.
