# US-006 Validation

## Proof Strategy

Use deterministic manifests and predictions to prove schema, integrity,
distribution, normalization, metric, redaction, and failure behavior. The final
acceptance run must validate all 100 referenced images and produce separate
Local Only and Accuracy Mode reports without creating a Calendar event.

## Test Plan

| Layer | Cases |
| --- | --- |
| Unit | Manifest v1/v2 and prediction parsing; authorization/review gates; normalization; field metrics; critical wrong-value rate; median latency; budget accounting |
| Integration | Image hash and external-private verification; duplicate/missing/unknown prediction rejection; OpenRouter key/cost contracts; redacted JSON report |
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
PYTHONPATH=packages/benchmark .venv/bin/python -m pytest packages/benchmark/tests -q
scripts/run-benchmark.sh validate --require-complete
scripts/run-benchmark.sh validate --require-real-world --require-second-reviewed
scripts/run-benchmark.sh validate --require-cloud-authorized openrouter
scripts/run-benchmark.sh score --mode local_only
scripts/run-benchmark.sh score --mode accuracy
```

## Acceptance Evidence

- Manifest versions 1 and 2, SHA-256 checks, public/private provenance,
  external-private storage, benchmark/OpenRouter authorization, expected
  ambiguity, independent review, composition, structured failure, redaction,
  language metrics, calibration/acceptance profiles, and zero-synthetic
  real-world gates are implemented; 45
  benchmark package tests pass.
- The benchmark-only API is disabled by default and has provider key-limit
  preflight, direct and fallback actual-cost resolution, serialized cumulative
  accounting, a hard $5 ceiling, and redacted status/run metadata; 25 FastAPI
  tests pass.
- The real-world pipeline freezes the acceptance manifest, runs Local Only over
  both sets before cloud use, caps the 20-item Accuracy calibration, projects
  the 100+ item cost with a 20% reserve, and refuses acceptance unless the
  reserved projection fits under both the remaining authorized $5 total and
  provider-key limit. Final metadata rejects incomplete requests, a changed
  model or manifest, failed quality gates, and combined budget overrun. This
  orchestration is tested without making a provider request.
- The checked-in generated corpus has 100 items: 70 Vietnamese/mixed, 30
  English, 49 challenging, and all required source categories.
- The production-source Local Only run passed every synthetic quality gate with
  zero critical wrong values, complete critical evidence, and about 155 ms
  median latency in the fresh 2026-07-15 run.
- The production-source Accuracy runner compiles and refuses to execute without
  `SNAPCAL_BENCHMARK_ALLOW_CLOUD=1`; a complete run is intentionally not
  claimed because it incurs provider cost.
- On 2026-07-15, bounded Apify discovery produced 565 unique Commons file URLs
  at about $0.16 total Apify usage. The rights-filtered importer resolved all
  565 records, found 412 machine-eligible files, and downloaded 180 unique
  review candidates (about 145 MB of content) across eight discovery categories.
  All 180 hashes verified. This is acquisition evidence only: sampled results
  include historical material, photos of posters, near-duplicates, and only a
  small Vietnam category, so event relevance, privacy, attribution, language,
  labels, and cloud authorization still require review.
- Five additional Vietnam-focused Apify runs on 2026-07-15 produced 125 raw
  records for $0.012 (about $0.23 total account usage after the runs). They
  remain quarantined acquisition candidates because many are site icons,
  signage, unrelated historical posters, or event photographs rather than
  calendar-ready posters. The final targeted MediaSearch run cost $0.003 and
  was stopped after its sample did not materially improve Vietnamese relevance.
- A local Apple Vision triage verified and scanned all 180 downloaded candidate
  hashes without cloud use. OCR succeeded for 162 items; 55 had date signals,
  54 had time signals, and only 32 met the preliminary event-image heuristic.
  After conservative language filtering, only 11 had a Vietnamese hint and
  only one was also a likely event image. The external review queue leaves all
  license, sanitation, cloud-authorization, annotation, and second-review
  counts at zero, proving that this acquisition pool is not the required
  Vietnamese/mixed acceptance corpus.
- The external review-template and promotion tools now keep all machine hints
  non-authoritative, require explicit rights/sanitation/annotation/cloud
  approvals, require distinct primary and second reviewers, verify hashes and
  safe paths, and publish only a fully valid 20-item calibration or 100+ item
  acceptance corpus. No candidate has been auto-approved or promoted.
- Final acceptance remains open for a licensed, sanitized non-synthetic corpus
  and complete Local Only plus Accuracy reports over that corpus.
