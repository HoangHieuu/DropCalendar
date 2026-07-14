# US-006 Validation

## Proof Strategy

Use deterministic manifests and predictions to prove schema, integrity,
distribution, normalization, metric, redaction, and failure behavior. The final
acceptance run must validate all 100 referenced images and produce separate
Local Only and Accuracy Mode reports without creating a Calendar event.

## Test Plan

| Layer | Cases |
| --- | --- |
| Unit | Manifest and prediction parsing; normalization; field metrics; critical wrong-value rate; median latency |
| Integration | Image hash verification; duplicate/missing/unknown prediction rejection; redacted JSON report |
| E2E | Validated 100-item corpus through Local Only and explicitly opted-in Accuracy Mode |
| Platform | Apple Vision runner on macOS; no Calendar adapter invocation |
| Performance | Median extraction latency reported per mode and language cohort |
| Logs/Audit | No image bytes, full OCR, prompts, credentials, or private event text in output |

## Fixtures

- Small deterministic valid corpus.
- Missing-image, hash-mismatch, duplicate-ID, incomplete-distribution, and
  unsanitized corpus cases.
- Correct, missing-field, wrong-critical-field, structured-failure, and
  malformed prediction cases.
- Final 100-item licensed and sanitized corpus.

## Commands

```bash
.venv/bin/python -m pytest packages/benchmark/tests -q
scripts/run-benchmark.sh validate --require-complete
scripts/run-benchmark.sh score --mode local_only
scripts/run-benchmark.sh score --mode accuracy
```

## Acceptance Evidence

- Version-1 manifest and prediction schemas, SHA-256 checks, redistribution and
  sanitization assertions, composition gates, structured failures, redacted
  reports, language-separated metrics, external corpus paths, and a
  zero-synthetic real-world gate are implemented; 9 package tests pass.
- The checked-in generated corpus has 100 items: 70 Vietnamese/mixed, 30
  English, 49 challenging, and all required source categories.
- The production-source Local Only run passed every synthetic quality gate with
  zero critical wrong values and about 137 ms median latency on 2026-07-14.
- The production-source Accuracy runner compiles and refuses to execute without
  `SNAPCAL_BENCHMARK_ALLOW_CLOUD=1`; a complete run is intentionally not
  claimed because it incurs provider cost.
- Final acceptance remains open for a licensed, sanitized non-synthetic corpus
  and complete Local Only plus Accuracy reports over that corpus.
