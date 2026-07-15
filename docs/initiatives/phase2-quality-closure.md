# Phase 2 Quality Closure

## Objective

Close extraction reliability with a private real-world Vietnamese-English
benchmark, cost-bounded Accuracy evaluation, benchmark-proven remediation, and
signed native macOS proof. Synthetic fixtures remain regression evidence only.

## Current Gate Status

| Gate | Status | Evidence / remaining work |
| --- | --- | --- |
| 0. Freeze baseline | complete | macOS, FastAPI, benchmark, Local Only, and UI-smoke baselines captured on 2026-07-15 |
| 1. Acquire lawful corpus | blocked on human review and source coverage | 180 Commons review files plus 125 newly discovered Apify records are quarantined externally; local triage found only 32 likely event images and one likely Vietnamese event image. The 180-row review template remains entirely pending; rights, sanitation, labels, authorization, and second review remain incomplete |
| 2. Correct benchmark contract | implemented | manifest v2, v1 compatibility, external-private enforcement, authorization and second-review gates, human review templates, and fail-closed private corpus promotion; 45 benchmark tests pass |
| 3. Enforce US$5 budget | implemented, live preflight pending | benchmark-only endpoint, provider key-limit preflight, actual/fallback cost, cumulative budget, managed loopback service, and redacted metadata; 25 API tests pass |
| 4. Produce dual-mode baseline | pending Gate 1 | Local Only synthetic regression passes; real calibration and acceptance reports do not yet exist |
| 5. Harden proven failures | pending Gate 4 | no real-world failure clusters are available yet |
| 6. Close native macOS proof | in progress | signed unit suite passes; the notch panel is below status-item level and the status item has an explicit accessibility identifier. Fresh UI click automation is blocked before test execution by Xcode timing out while enabling automation mode; Finder drag plus remaining OAuth/MapKit/privacy platform proofs remain open |
| 7. Declare proof-ready MVP | pending | requires all prior gates and redacted real-world reports |

## Cost Ledger

- Apify discovery on 2026-07-15: five bounded focused runs, 125 raw records,
  $0.012. The final low-relevance query was stopped without further runs.
- Existing Apify account usage after discovery: approximately $0.23 of $30.
- OpenRouter acceptance spend in this initiative so far: $0.00.
- Maximum authorized future OpenRouter benchmark spend: $5 total, subject to a
  dedicated key limit and successful preflight.

## Stop Conditions

- Do not send a candidate to OpenRouter unless its manifest row explicitly
  authorizes benchmark use and OpenRouter processing.
- Do not weaken the schema, hash, sanitation, external-storage, or second-review
  gates to make an incomplete corpus pass.
- Do not create a Calendar event without explicit confirmation of the exact
  event and target calendar.
- Do not claim Phase 2 or MVP completion from synthetic results.
