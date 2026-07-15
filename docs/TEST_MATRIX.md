# SnapCal Test Matrix

The durable operational matrix is queried with:

```bash
scripts/bin/harness-cli query matrix --active --summary
```

This file defines the product proof vocabulary. A behavior becomes an
operational row only when its story is accepted. Do not mark behavior
implemented without fresh executable evidence.

## Non-Negotiable Safety Gates

| ID | Behavior | Required proof |
| --- | --- | --- |
| SAFE-01 | No calendar provider call before explicit review confirmation | application unit plus integration spy; E2E/platform flow |
| SAFE-02 | No date is invented without source evidence | parser unit suite plus benchmark negative cases |
| SAFE-03 | Date/time disagreement becomes an ambiguity | deterministic unit cases plus extraction contract fixture |
| SAFE-04 | Critical fields preserve evidence and confidence | schema/contract tests plus review UI assertion |
| SAFE-05 | No app-owned raw screenshot copy is retained by default after success; user originals are untouched | persistence integration and platform filesystem proof |
| SAFE-06 | Logs exclude image bytes, full OCR, tokens, and private payloads | log capture/redaction tests |
| SAFE-07 | Local-only mode makes no cloud call | adapter spy/network isolation proof |
| SAFE-08 | Multiple extracted events require independent confirmations and provider calls | application state test with Calendar spy plus platform review flow |
| SAFE-09 | Anonymous Local Only makes zero account, billing, backend, database, or provider calls | client spy plus network-isolation regression |
| SAFE-10 | One successful screenshot consumes exactly one unit; all failure/fallback paths release quota | PostgreSQL transaction, idempotency, and provider-failure integration tests |
| SAFE-11 | Paddle redirects never grant entitlement; only verified ordered webhooks update access | signature, deduplication, ordering, and `/me` integration tests |
| SAFE-12 | Hosted retry data is device-sealed and inaccessible after 15 minutes | cross-key decryption rejection plus expiry and cleanup integration tests |
| SAFE-13 | Hosted logs and records exclude image, OCR, prompt, event fields, email, and credentials | log capture plus schema/privacy scan |

## Functional Proof Areas

| Area | Unit | Integration | E2E | Platform | Benchmark |
| --- | --- | --- | --- | --- | --- |
| Image validation | format, count, corrupt metadata | import boundary | invalid/valid flow | clipboard/drop/share | fixture coverage |
| Vietnamese-English normalization | abbreviations, diacritics, mixed text | extraction payload | editable draft | locale/timezone | language-separated accuracy |
| Date/time/timezone | relative dates, all-day, conflict, past warning | provider-to-domain parse | review warnings | system timezone | critical error rate |
| Location | raw preservation, online/hybrid | Places candidates | user choice | permission/error state | location accuracy |
| Review | enablement, edit override, multi-draft navigation, state machine | per-draft persistence | confirm/cancel/retry per event | macOS/iOS/Android UI | correction rate |
| Calendar | mapping, reminder limits, independent confirmations | OAuth and Calendar fake/server | success/failure/retry per event | redirect/keychain | create success rate |
| Duplicates | hash and composite signals | local history | warning override | local storage | warning precision |
| Privacy | retention policy | deletion and redacted logs | history controls | filesystem/keychain | corpus sanitation |
| Paid beta | plans, entitlement states, quota math | auth, Paddle, PostgreSQL, idempotency | checkout-to-webhook-to-extraction fake | account settings and Keychain | 20-call cost/latency calibration |
| Delivery | configuration validation | migration and container health | staged digest promotion | Developer ID/notarization/Sparkle | 50-user provider-fake load |

Local Only semantic-rule proof includes tomorrow/today resolution from capture
time, weekday conflicts, event-start versus door-time preference, event-date
versus registration-deadline ranking, conservative `OO` correction, and
specific-location ranking. These rules must remain zero-cloud and visible as
deterministic rather than model-backed behavior.

## Benchmark Gates

The licensed real-world accuracy benchmark below is deferred from the paid-beta
release gate because the current product quality is accepted. Keep these gates
for future accuracy claims; do not represent generated fixtures as real-world
evidence.

- At least 100 licensed/sanitized screenshots: 50 Vietnamese or mixed, 30
  English, and 20 noisy/decorative examples.
- Report Vietnamese and English title/date/time/location metrics separately.
- Track critical wrong-date/wrong-time rate and median extraction latency.
- Every item yields one or more valid drafts or a structured failure reason.
- Real-world rows use manifest v2, stay outside Git, and pass benchmark-use,
  provider authorization, hash, sanitation, and independent-review gates.
- Accuracy preflight proves a dedicated provider key limit no greater than $5;
  actual cumulative cost is recorded and unverifiable cost aborts.
- Real-world acceptance is frozen by manifest hash; a completed 20-item
  calibration projects 100+ item cost with a 20% reserve, and acceptance is
  refused unless the reserved projection fits the remaining combined $5
  authorization and provider-key limit.
- Re-run after OCR engine, prompt, schema, parser, or normalization changes.

## Paid Beta Release Gates

- Exactly 20 sanitized live Accuracy fixtures pass the calibration checker
  before live checkout is enabled.
- Mean provider cost is at most US$0.005, p95 cost is at most US$0.01, and the
  projected 100-call average is at most US$0.50 per subscriber.
- Warm pre-provider backend overhead is below 500 ms p95; each quota
  transaction is below 100 ms p95; end-to-end Accuracy is below five seconds
  median and ten seconds p95.
- Fifty simulated users cannot duplicate quota, exhaust the configured database
  pool, or exceed the bounded provider call count.
- Production promotion uses the exact staging image digest after an explicit
  one-off migration. Tagged macOS artifacts must pass Developer ID signing,
  notarization, stapling, Gatekeeper assessment, and Sparkle signature checks.
- No live provider, billing, production deployment, or Calendar write is part
  of automated repository proof without explicit operator/user authorization.

## Proof Status

US-000 proves that the source spec is decomposed into living contracts. US-001
adds executable proof for one-image validation, corrupt/unsupported rejection,
Vietnamese and English date/time extraction, no-event refusal, ambiguity
surfacing, and valid/failure model transitions. US-002 adds unit and adapter
proof for timed/all-day Calendar mapping, PKCE/state validation, strict provider
responses, recoverable errors, and the rule that request/cancel paths make zero
provider calls while confirmation makes exactly one. US-003 adds layout-aware
OCR, all-day range semantics, opt-in Gemini proxy contracts, strict response
validation, visible fallback, and executable proof that Local Only makes zero
cloud calls and the client contains no provider credential. US-004 replaces the
direct provider adapter with OpenRouter, uses strict JSON Schema output, keeps
Bearer authorization server-side, redacts upstream failures, and defaults to
`google/gemini-3.1-flash-lite`. US-005 adds deterministic top-center panel
geometry, first-supported-image selection, unsupported-drop refusal, and a
shared-model integration path that still lands in review. Its UI smoke also
proves pointer hover expands once and keeps a stable frame instead of feeding
transient tracking exits back into panel resizing. US-006 adds strict
corpus integrity/distribution checks, redacted language-separated scoring, a
100-image generated regression corpus, manifest-v2 authorization and review
gates, and separate production-source Local Only and explicitly cloud-opted
Accuracy runners. Its benchmark-only service preflights a provider-limited key,
enforces a $5 process ceiling, resolves actual request cost, and leaves the
normal app endpoint cost-free. US-007 adds deterministic
relative-date, weekday, deadline/event-date, door/start-time, OCR correction,
and location-ranking rules with visible non-LLM disclosure. US-009 adds
`MenuBarExtra` and bounded in-memory clipboard intake. US-010 adds minimized
SQLite draft persistence, schema migration, reopen/delete behavior, and no
image/full-OCR storage. US-011 adds provider-bounded reminders, local duplicate
warnings, explicit-only MapKit candidates, default-off AES-GCM screenshot
history, and scoped Clear All deletion. US-013 extends the supplied SPEC with
bounded multiple-event extraction, schema-version-2 provider arrays, ordered
one-at-a-time review, per-position duplicate identity, and executable proof
that every Calendar write still needs a distinct confirmation.

US-014 adds hosted configuration, SQLAlchemy/Alembic server state, rotating
device sessions, authenticated multipart `/v2` extraction, atomic quota and
idempotency, bounded provider cost accounting, and device-sealed 15-minute
retry envelopes while preserving `/v1`. US-015 adds hosted Paddle checkout and
portal adapters plus signature-verified, deduplicated, ordered webhook-owned
entitlements. US-016 adds the macOS Account & Billing surface, identity consent,
entitlement-aware Accuracy, bounded JPEG preprocessing, overlapping OCR/cloud
work, `/me` warm-up, and Keychain retry keys without changing Local Only.
US-017 adds the container, migration job, Singapore Terraform, immutable digest
promotion, release workflow, Developer ID/notarization/Sparkle automation, and
operational runbook. Live external activation remains operator-owned evidence.

Fresh combined proof on 2026-07-15: the macOS suite executes 109 tests with 108
passing, including paid-beta account, image, Keychain, retry, and
benchmark-budget handling, with one environment-dependent Data Protection
Keychain case skipped. An earlier team-signed run passed the
isolated Data Protection Keychain round trip; the FastAPI suite passes all 48
tests against PostgreSQL 17; the benchmark package passes 47 tests; and the
production Local Only runner scores all 100 generated fixtures with zero
critical wrong values. The latest team-signed macOS UI smoke passes
clipboard-to-review persistence and stable notch hover.
Its prior menu-bar case reported that the status item existed but was not
hittable; the notch panel has since moved below `.statusBar` level and the
status item now has an explicit SnapCal accessibility label. A fresh UI click
result is still open because Xcode currently times out enabling automation mode
before any test method starts. No UI smoke creates a Calendar event.
Native inspection shows the deterministic Local Only disclosure and
default-off encrypted screenshot setting. The generated corpus remains
synthetic-only; licensed real-world Local Only/Accuracy reports, direct notch
drag/deletion smoke, live MapKit candidates, real-token relaunch reuse, and
team-signed disconnect/reconnect remain open platform or user-owned proofs.
