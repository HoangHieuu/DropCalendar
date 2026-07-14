# US-007 Design

## Domain Model

Date evidence records whether its value was inferred from capture context.
Candidate selection uses explicit, reviewable relevance rules. Multiple dates
and weekday conflicts remain domain ambiguities rather than silent guesses.

## Application Flow

1. Apple Vision produces text, confidence, and layout regions on-device.
2. Deterministic rules collect date, time, title, and location candidates.
3. Intent markers rank event starts above door times and event dates above
   registration deadlines.
4. Relative dates resolve only from the preserved capture time and timezone.
5. Consistency checks add ambiguities for competing dates or weekday conflicts.
6. The review UI discloses that Local Only has limited semantic understanding.

## Interface Contract

No network or public API change. `EventDraft` continues to carry normalized
values, raw evidence, confidence, inference state, and ambiguities.

## Data Model

No persistence or migration.

## UI / Platform Impact

The import screen identifies Local Only as Apple Vision OCR plus deterministic
rules, not a language model, and recommends Accuracy Mode when context matters.

## Observability

Unit and benchmark results record fixture IDs and mismatch classes only. Raw OCR
and event values remain excluded from operational logs.

## Alternatives Considered

1. Add a local LLM immediately: deferred to a benchmark-driven feasibility
   decision because model size, hardware support, latency, and licensing remain
   unresolved.
2. Route weak Local Only results to OpenRouter automatically: rejected because
   it would violate explicit cloud consent.
