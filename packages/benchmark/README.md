# SnapCal Extraction Benchmark

This package validates and scores the versioned Vietnamese-English extraction
corpus. It never creates a Calendar event and does not log image bytes, raw OCR,
prompts, credentials, or event-field values.

## Contracts

The checked-in corpus manifest is `corpus/manifest.jsonl`. Its generated rows
use schema version `1` and reference one image relative to the manifest. Schema
version `2` is required for real-world acceptance and adds benchmark/cloud
authorization, expected ambiguities, and independent annotation review.
Validation fails unless the image digest, provenance, storage boundary, and
sanitization assertion pass.

Predictions are JSON Lines with one row per corpus item and extraction mode.
Reports contain aggregates plus fixture IDs and mismatch field names only.

## Commands

```bash
PYTHONPATH=packages/benchmark .venv/bin/python -m pytest packages/benchmark/tests -q
scripts/run-benchmark.sh validate
scripts/run-benchmark.sh validate --require-complete
scripts/run-benchmark.sh validate --require-real-world --require-second-reviewed
scripts/run-benchmark.sh validate --require-cloud-authorized openrouter
scripts/run-benchmark.sh score --mode local_only
scripts/run-benchmark.sh score --mode accuracy
scripts/run-local-benchmark.sh
# Explicit opt-in: sends the corpus through the configured Accuracy service.
SNAPCAL_BENCHMARK_ALLOW_CLOUD=1 scripts/run-accuracy-benchmark.sh
```

For final real-world acceptance, keep licensed source material in an
owner-controlled directory and point both runners at its manifest. The
real-world flag fails if even one row is synthetic, if a row is not version 2,
or if the manifest/corpus is inside the repository. Private benchmark
permission is sufficient: version-2 provenance may set `redistributable=false`
when assets remain external. Hash, sanitization, authorization, annotation,
language, difficulty, and source-category gates still apply:

```bash
export SNAPCAL_BENCHMARK_MANIFEST=/absolute/path/to/snapcal-real/manifest.jsonl
export SNAPCAL_BENCHMARK_RUNS_DIR=/absolute/path/to/snapcal-real/runs
export SNAPCAL_BENCHMARK_REPORT_DIR=/absolute/path/to/snapcal-real/reports
export SNAPCAL_BENCHMARK_REQUIRE_REAL_WORLD=1

scripts/run-local-benchmark.sh
SNAPCAL_BENCHMARK_ALLOW_CLOUD=1 scripts/run-accuracy-benchmark.sh
```

Do not set the cloud opt-in until every corpus item is authorized for OpenRouter
processing and provider cost has been explicitly accepted. Real-world Local
Only adds the second-review gate. Real-world Accuracy adds both the
second-review and OpenRouter-authorization gates. Neither runner can create
Calendar events.

The final private-corpus sequence is orchestrated as one fail-closed command:

```bash
SNAPCAL_BENCHMARK_ALLOW_CLOUD=1 \
scripts/run-real-world-benchmark-pipeline.sh \
  /absolute/path/to/calibration/manifest.jsonl \
  /absolute/path/to/acceptance/manifest.jsonl \
  /absolute/path/to/snapcal-real-world-runs
```

Before any cloud request, this validates exactly 20 calibration items and at
least 100 acceptance items against the real-world, OpenRouter, hash,
sanitation, and second-review gates. It freezes the acceptance manifest hash,
runs Local Only on both sets, and verifies that the freeze did not change. The
Accuracy calibration has a default process cap of $1; setting
`SNAPCAL_CALIBRATION_BUDGET_USD` may lower it. Its actual per-item cost is
projected across the acceptance set with a 20% reserve. Acceptance starts only
when that reserved projection fits both the remaining authorized $5 total and
the provider key's remaining limit. Final metadata requires 20 and 100+
completed requests, the same model, passing Accuracy quality gates, an
unchanged manifest, and combined cost no greater than $5. Predictions, service
logs, and reports all remain in the external output directory.

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
`SNAPCAL_BENCHMARK_ALLOW_CLOUD=1` is set. By default it starts a dedicated
benchmark-mode loopback service on a free port and stops only that process. The
service refuses preflight unless the OpenRouter key has a finite provider-side
limit no greater than $5 and at least the configured process budget remaining.
The benchmark-only endpoint reports actual request/cumulative/remaining cost,
using generation metadata when completion usage omits cost. The script writes
redacted preflight, usage, score, manifest-hash, revision, latency, and abort
metadata. It never invokes the Calendar adapter. Synthetic-only results remain
regression evidence, not a real-world accuracy claim.

## Licensed Candidate Intake

Apify may be used for bounded source discovery, but its downloaded category
thumbnails are not benchmark assets. The Commons importer resolves each
discovered Wikimedia file through the Commons API, accepts only public-domain,
CC0, CC BY, or CC BY-SA metadata, and downloads a paced review copy requested
at a 1600-pixel target width:

```bash
export PYTHONPATH="$PWD/packages/benchmark${PYTHONPATH:+:$PYTHONPATH}"
.venv/bin/python -m snapcal_benchmark.commons_import \
  --output-dir /absolute/path/to/snapcal-commons-review \
  /absolute/path/to/apify-*/apify-output-metadata.json
```

The default limit is 180 files, each capped at 10 MB. Commons may select one of
its standardized thumbnail widths instead of the exact requested width.
Commons metadata is cached so an interrupted or rate-limited import can resume
without repeating resolved API requests. Candidate images, attribution records,
and rejection records stay in the owner-controlled output directory, outside
Git.

Import is deliberately not manifest generation. Every candidate starts with
`machine_license_allowlisted=true`, but `redistributable=false`,
`license_reviewed=false`, `sanitized=false`, and
`cloud_processing_authorized=false`. A person must confirm that the image is an
event, verify its license and attribution, check for private data, label the
language/difficulty/expected fields, and explicitly authorize any Accuracy Mode
processing before the item can enter the real-world benchmark.

Run the local-only review triage after import to rank likely event images
without uploading any candidate or consuming provider credit:

```bash
scripts/triage-benchmark-candidates.sh \
  /absolute/path/to/snapcal-commons-review/candidates.jsonl \
  /absolute/path/to/snapcal-commons-review/triage
```

The script verifies every candidate hash, runs production Apple Vision OCR,
and writes `ocr-results.jsonl`, `review-queue.jsonl`,
`review-worksheet.csv`, and `triage-summary.json` in the external directory.
Those files may contain item-level OCR text and must not be copied into Git.
Language, source, difficulty, date, time, and event-likelihood values are only
review hints. The tool deliberately leaves license review, sanitation, cloud
authorization, ground-truth annotation, and critical-field second review at
zero and never generates an acceptance manifest.

Prepare an external human-review file without copying OCR text or granting any
approval automatically:

```bash
scripts/prepare-benchmark-review.sh \
  /absolute/path/to/snapcal-commons-review/candidates.jsonl \
  /absolute/path/to/snapcal-commons-review/triage/review-queue.jsonl \
  /absolute/path/to/snapcal-commons-review/review-decisions.jsonl
```

Every row starts as `pending`, with rights review, sanitation, benchmark/cloud
authorization, ground-truth annotation, and second review set to false. Machine
hints are included only to prioritize review. A person must fill the canonical
event fields, capture time, IANA timezone, source category, difficulty,
provenance, authorization reference, and two distinct reviewer references.

After review, promote calibration and acceptance sets separately. Promotion
copies only explicitly approved, hash-verified images into a new external
private corpus, never overwrites an existing directory, and deletes its staging
directory on any error:

```bash
scripts/promote-benchmark-review.sh calibration \
  /absolute/path/to/candidates.jsonl \
  /absolute/path/to/calibration-decisions.jsonl \
  /absolute/path/to/calibration-corpus

scripts/promote-benchmark-review.sh acceptance \
  /absolute/path/to/candidates.jsonl \
  /absolute/path/to/acceptance-decisions.jsonl \
  /absolute/path/to/acceptance-corpus
```

Calibration promotion requires exactly 20 real-world, sanitized,
OpenRouter-authorized, independently reviewed items. Acceptance promotion also
enforces the full 100-item language, challenge, and source-category contract.
Pending and rejected rows are ignored; missing approvals, identical reviewers,
unsafe paths, altered hashes, incomplete labels, or an in-repository output fail
closed before a corpus is published.
