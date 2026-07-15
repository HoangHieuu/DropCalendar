# 0020 Private Benchmark Authorization And Cost Boundary

Date: 2026-07-15

## Status

Accepted

## Context

The checked-in version-1 corpus is synthetic regression evidence. Real-world
Phase 2 acceptance requires licensed or privately permitted screenshots whose
redistribution, privacy, annotation, and OpenRouter-processing permissions are
not equivalent. The normal Accuracy endpoint also intentionally omits provider
cost details, so reusing it for a 100-item cloud benchmark would not enforce the
authorized US$5 ceiling or prove actual request cost.

## Decision

- Keep manifest version 1 valid for the checked-in synthetic corpus and add
  manifest version 2 for real-world acceptance.
- Version 2 records benchmark-use authorization, an explicit cloud-processor
  allowlist, an opaque authorization reference, expected ambiguity fields, and
  independent critical-field review with a review timestamp.
- Allow `provenance.redistributable=false` only for assets that remain outside
  repository-owned directories. Real-world manifests and images remain in an
  owner-controlled external directory.
- Fail real-world runs unless every row is version 2, non-synthetic,
  hash-verified, sanitized, benchmark-authorized, and independently reviewed.
  Accuracy acceptance additionally requires `openrouter` in each row's cloud
  processor allowlist.
- Keep `POST /v1/extract` unchanged for the app. Register
  `POST /v1/benchmark/extract` only in explicit benchmark mode.
- Require a dedicated OpenRouter key whose provider-side limit is finite and no
  more than US$5. Verify it through `GET /api/v1/key` before any benchmark
  image is submitted.
- Read request cost from the non-streaming completion usage response. If absent,
  query generation metadata by generation ID. Abort if cost still cannot be
  determined.
- Serialize benchmark requests through a process-local budget counter, return
  request/cumulative/remaining cost, refuse requests after the configured
  ceiling, and preserve the provider key limit as single-request overshoot
  protection.
- Run Accuracy acceptance through a dedicated loopback service process on a
  free port, stop only that process, and write redacted preflight, usage, score,
  manifest-hash, source-revision, latency, request-count, and abort metadata.

## Alternatives Considered

1. Require public redistribution for every real-world screenshot. Rejected
   because private benchmark permission is sufficient when assets never enter
   Git or public reports.
2. Store authorization in a separate informal checklist. Rejected because a
   missing or mismatched checklist could allow extraction to begin.
3. Reuse `/v1/extract` and estimate cost from token counts. Rejected because the
   production response contract must stay stable and estimated pricing is not
   actual billed cost.
4. Rely only on a local counter. Rejected because the cost of one request is
   known only after completion; the provider-side key limit is the final hard
   protection.
5. Use the account's general OpenRouter key. Rejected because unrelated traffic
   and a higher or unlimited key ceiling would invalidate benchmark accounting.

## Consequences

Positive:

- Acquisition candidates cannot be promoted into cloud evaluation without
  machine-enforced permission and annotation evidence.
- Private licensed data can support acceptance without being redistributed.
- Normal application behavior remains unchanged while benchmark spend is
  independently visible and bounded.

Tradeoffs:

- A person still must review licenses, sanitation, expected fields,
  ambiguities, and OpenRouter permission; Apify cannot supply those facts.
- Final Accuracy acceptance cannot run until a dedicated provider-limited key
  and a complete externally stored version-2 corpus both pass preflight.
- A single request may consume the last remaining provider allowance before its
  actual cost is returned, which is why the provider-side limit is mandatory.

## Follow-Up

- Complete the 20-item calibration and frozen 100-item acceptance manifests.
- Obtain independent second review for date, time, timezone, and travel-critical
  location labels.
- Run Local Only first, then the authorized Accuracy calibration and projected
  acceptance sequence.
