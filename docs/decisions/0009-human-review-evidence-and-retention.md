# 0009 Human Review, Evidence, And Retention

Date: 2026-07-13

## Status

Accepted

## Context

SnapCal processes screenshots that may contain private data and converts noisy
text into calendar writes. A wrong date/time can harm trust, while cloud
providers, logs, and retained images create privacy risk.

## Decision

- Every MVP calendar write requires explicit user confirmation from a review
  state.
- Date, start time, timezone, and travel-critical location preserve raw
  evidence, normalized value, confidence, and inference/ambiguity state.
- Model or OCR disagreement never silently resolves a critical field.
- Raw screenshots are deleted by default after successful extraction.
- Full OCR, image bytes, credentials, and private provider payloads are excluded
  from operational logs.
- Cloud processing is disclosed; local-only mode must prevent cloud calls.

These are product and architecture invariants, not optional UI polish.

## Alternatives Considered

1. Auto-create high-confidence events. Rejected for the MVP.
2. Store screenshots by default for convenience. Rejected because private data
   retention is not necessary for the core outcome.
3. Retain normalized fields without evidence. Rejected because users and tests
   need to understand critical inferences.

## Consequences

Positive:

- Users can correct risky output before an external write.
- Extraction behavior is auditable and benchmarkable.
- Default storage and logs minimize private-data exposure.

Tradeoffs:

- Review adds one explicit step.
- Evidence-bearing models and deletion proof increase implementation work.

## Follow-Up

- Require these invariants in every extraction, persistence, review, calendar,
  and local-only story.
