# 0015 Versioned Extraction Benchmark

Date: 2026-07-14

## Status

Accepted

## Context

SnapCal has deterministic Local Only extraction and opt-in OpenRouter Accuracy
Mode, but it has no corpus or repeatable metric command. A successful live
poster proves provider operability, not Vietnamese-English accuracy. Screenshot
fixtures may also contain private data or material that cannot be redistributed.

## Decision

- Define a versioned JSON benchmark-item contract and validate every manifest
  before extraction or scoring.
- Require each image to have a stable identifier, SHA-256 digest, language,
  source category, difficulty labels, capture time, timezone, expected fields,
  redistribution basis, and an explicit sanitization assertion.
- Reject a corpus item whose image is missing, hash mismatches, redistribution
  basis is blank, or sanitization is not affirmed.
- Score Local Only and Accuracy Mode separately from prediction JSON Lines.
- Report Vietnamese and English title/date/time/location accuracy separately,
  critical wrong-date/wrong-time rate, structured failure rate, and median
  extraction latency.
- Keep raw OCR, image bytes, prompts, credentials, and private event text out of
  metric output and logs.
- Treat synthetic or generated images as useful regression fixtures but label
  them explicitly; do not present a synthetic-only result as real-world quality.

## Alternatives Considered

1. Use XCTest examples as the benchmark. Rejected because they do not provide
   corpus distribution, licensing, or language-separated metrics.
2. Check in arbitrary web screenshots. Rejected because provenance,
   redistribution rights, and private-data safety would be unknown.
3. Judge quality from a few successful live runs. Rejected because this cannot
   quantify error rates or regressions.

## Consequences

Positive:

- Parser and model changes gain repeatable, language-separated evidence.
- Corpus privacy and licensing failures are detected before a run.
- Local Only limitations can be measured instead of described subjectively.

Tradeoffs:

- Building the first 100-item corpus requires deliberate fixture acquisition,
  labeling, sanitization, and review.
- Real-world claims remain unavailable until the corpus includes enough
  licensed non-synthetic material.

## Follow-Up

- Implement US-006 and publish the first validated 100-item corpus report.
- Use benchmark failures to select Local Only parser work and any future
  on-device semantic model rather than choosing technology first.
