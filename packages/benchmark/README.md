# SnapCal Extraction Benchmark

This package validates and scores the versioned Vietnamese-English extraction
corpus. It never creates a Calendar event and does not log image bytes, raw OCR,
prompts, credentials, or event-field values.

## Contracts

The official corpus manifest is `corpus/manifest.jsonl`. Every row uses schema
version `1` and references one image relative to the manifest. Validation fails
unless the image digest, redistribution basis, and sanitization assertion pass.

Predictions are JSON Lines with one row per corpus item and extraction mode.
Reports contain aggregates plus fixture IDs and mismatch field names only.

## Commands

```bash
.venv/bin/python -m pytest packages/benchmark/tests -q
scripts/run-benchmark.sh validate
scripts/run-benchmark.sh validate --require-complete
scripts/run-benchmark.sh score --mode local_only
scripts/run-benchmark.sh score --mode accuracy
scripts/run-local-benchmark.sh
# Explicit opt-in: sends the corpus through the configured Accuracy service.
SNAPCAL_BENCHMARK_ALLOW_CLOUD=1 scripts/run-accuracy-benchmark.sh
```

For final real-world acceptance, keep licensed source material in an
owner-controlled directory and point both runners at its manifest. The
real-world flag fails if even one row is synthetic, while the existing
provenance, redistribution, sanitization, hash, language, difficulty, and
source-category gates still apply:

```bash
export SNAPCAL_BENCHMARK_MANIFEST=/absolute/path/to/snapcal-real/manifest.jsonl
export SNAPCAL_BENCHMARK_RUNS_DIR=/absolute/path/to/snapcal-real/runs
export SNAPCAL_BENCHMARK_REPORT_DIR=/absolute/path/to/snapcal-real/reports
export SNAPCAL_BENCHMARK_REQUIRE_REAL_WORLD=1

scripts/run-local-benchmark.sh
SNAPCAL_BENCHMARK_ALLOW_CLOUD=1 scripts/run-accuracy-benchmark.sh
```

Do not set the cloud opt-in until every corpus item is authorized for that
processing and provider cost has been explicitly accepted. Neither runner can
create Calendar events.

The complete gate requires at least 100 items, including 50 Vietnamese or mixed,
30 English, 20 challenging examples, and every source category named by the
product contract. Synthetic fixtures must be labeled and cannot support a
real-world accuracy claim by themselves. `--require-real-world` enforces a
zero-synthetic corpus.

`scripts/run-local-benchmark.sh` compiles a narrow macOS runner from the
production Apple Vision and deterministic extractor sources. It has no cloud or
Calendar dependency, writes versioned predictions, and produces the Local Only
report under `.build/benchmark/`.

`scripts/run-accuracy-benchmark.sh` compiles the production Apple Vision and
Accuracy Mode client sources, but refuses to run unless
`SNAPCAL_BENCHMARK_ALLOW_CLOUD=1` is set. A complete run sends all corpus images
through the configured OpenRouter-backed service and can incur provider cost.
The runner never invokes the Calendar adapter and writes only redacted
predictions. Synthetic-only results remain regression evidence, not a
real-world accuracy claim.
