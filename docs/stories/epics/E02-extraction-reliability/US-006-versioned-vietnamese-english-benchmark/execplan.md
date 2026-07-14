# US-006 Exec Plan

## Goal

Make Vietnamese-English extraction quality measurable and safe enough to drive
the remaining Phase 2 implementation.

## Scope

In scope:

- Versioned manifest, prediction, and report contracts.
- Corpus integrity, provenance, licensing, and sanitization validation.
- Language-separated field, critical-error, failure, and latency metrics.
- A repeatable CLI, tests, and the first 100-item corpus.
- Separate Local Only and Accuracy Mode reports.

Out of scope:

- Production telemetry or collection of user screenshots.
- Treating synthetic-only results as real-world quality.
- Calendar writes during benchmark execution.

## Risk Classification

Risk flags:

- Data model.
- Audit/security.
- External systems.
- Existing behavior.
- Weak proof.
- Multi-domain.

Hard gates:

- Private screenshot retention and external provider processing.

## Work Phases

1. Implement schemas, validation, scoring, and deterministic tests.
2. Add a small redistributable seed corpus and prove end-to-end reporting.
3. Add extraction adapters for Local Only and explicitly opted-in Accuracy Mode.
4. Expand to 100 licensed and sanitized items with required distribution.
5. Run both modes, publish redacted results, and classify failure clusters.
6. Update Phase 2 product, story, decision, and Harness proof state.

## Stop Conditions

Pause for human confirmation if a fixture lacks clear redistribution rights,
contains private information that cannot be sanitized, Accuracy Mode would run
without explicit opt-in, or a benchmark gate would need to be weakened.
