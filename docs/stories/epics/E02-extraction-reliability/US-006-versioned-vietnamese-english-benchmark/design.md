# US-006 Design

## Domain Model

- `BenchmarkItem`: immutable identity, image digest, language, source category,
  difficulty labels, capture context, expected event fields, provenance, and
  sanitization state.
- `BenchmarkPrediction`: extraction mode, draft or structured failure, proposed
  fields, critical-field evidence presence, ambiguity fields, and latency.
- `BenchmarkReport`: corpus counts plus metrics separated by extraction mode and
  language cohort.

Wrong critical values are distinct from missing values. A wrong date or time
contributes to the critical-error rate; a missing value reduces field accuracy
without being silently treated as correct.

## Application Flow

1. Validate every manifest row and referenced image before a run.
2. Verify the SHA-256 digest, provenance, redistribution basis, and sanitization
   assertion.
3. Run a selected extractor or consume its versioned prediction JSON Lines.
4. Reject missing, duplicate, unknown, or malformed predictions.
5. Score normalized fields and emit a redacted JSON and text report.
6. Exit nonzero when corpus completeness or configured quality gates fail.

## Interface Contract

The benchmark CLI provides:

- `validate --manifest <path> [--require-complete]`
- `score --manifest <path> --predictions <path> --output <path>`

Schema version `1` is required for manifest rows, predictions, and reports.
Dates use `YYYY-MM-DD`, timed values use RFC 3339 with an explicit offset, and
all-day end dates use the inclusive review-domain convention.

## Data Model

The official manifest and redistributable images live under
`packages/benchmark/corpus/`. Reports are generated and ignored. No database or
user screenshot history is introduced.

## UI / Platform Impact

No customer UI changes. The benchmark is a developer command. Local Only and
Accuracy Mode remain separate result cohorts.

## Observability

Reports contain fixture identifiers, aggregate metrics, normalized failure
classes, and latency only. They exclude image bytes, full OCR, prompts,
credentials, and private event content.

## Alternatives Considered

1. XCTest-only measurement: rejected because corpus integrity and metric output
   would remain implicit.
2. Provider-only measurement: rejected because Local Only is a product mode and
   must be measured independently.
3. Unversioned CSV labels: rejected because nested evidence, provenance, and
   schema evolution need typed validation.
