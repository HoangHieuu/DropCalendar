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
4. Add manifest version 2 with benchmark/cloud authorization, external-private
   storage enforcement, expected ambiguities, and independent review gates.
5. Add the disabled-by-default benchmark endpoint, dedicated-key preflight,
   actual cost accounting, $5 ceiling, and redacted run metadata.
6. Expand to a reviewed 20-item calibration set and frozen 100-item licensed,
   sanitized, authorized acceptance set with the required distribution.
7. Run Local Only first, project cloud cost from calibration, then run the
   authorized Accuracy acceptance only if budget remains.
8. Publish redacted results, classify failure clusters, and update Phase 2
   product, story, decision, and Harness proof state.

## Stop Conditions

Pause for human confirmation if a fixture lacks clear public or private
benchmark permission, contains private information that cannot be sanitized,
has not completed critical-field second review, lacks explicit OpenRouter
authorization, Accuracy Mode would run without explicit opt-in, provider key
limits exceed $5, or a benchmark gate would need to be weakened.
