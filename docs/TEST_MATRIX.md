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

## Functional Proof Areas

| Area | Unit | Integration | E2E | Platform | Benchmark |
| --- | --- | --- | --- | --- | --- |
| Image validation | format, count, corrupt metadata | import boundary | invalid/valid flow | clipboard/drop/share | fixture coverage |
| Vietnamese-English normalization | abbreviations, diacritics, mixed text | extraction payload | editable draft | locale/timezone | language-separated accuracy |
| Date/time/timezone | relative dates, all-day, conflict, past warning | provider-to-domain parse | review warnings | system timezone | critical error rate |
| Location | raw preservation, online/hybrid | Places candidates | user choice | permission/error state | location accuracy |
| Review | enablement, edit override, state machine | draft persistence | confirm/cancel/retry | macOS/iOS/Android UI | correction rate |
| Calendar | mapping, reminder limits | OAuth and Calendar fake/server | success/failure/retry | redirect/keychain | create success rate |
| Duplicates | hash and composite signals | local history | warning override | local storage | warning precision |
| Privacy | retention policy | deletion and redacted logs | history controls | filesystem/keychain | corpus sanitation |

Local Only semantic-rule proof includes tomorrow/today resolution from capture
time, weekday conflicts, event-start versus door-time preference, event-date
versus registration-deadline ranking, conservative `OO` correction, and
specific-location ranking. These rules must remain zero-cloud and visible as
deterministic rather than model-backed behavior.

## Benchmark Gates

- At least 100 licensed/sanitized screenshots: 50 Vietnamese or mixed, 30
  English, and 20 noisy/decorative examples.
- Report Vietnamese and English title/date/time/location metrics separately.
- Track critical wrong-date/wrong-time rate and median extraction latency.
- Every item yields a valid draft or a structured failure reason.
- Re-run after OCR engine, prompt, schema, parser, or normalization changes.

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
shared-model integration path that still lands in review. US-006 adds strict
corpus integrity/distribution checks, redacted language-separated scoring, a
100-image generated regression corpus, and separate production-source Local
Only and explicitly cloud-opted Accuracy runners. US-007 adds deterministic
relative-date, weekday, deadline/event-date, door/start-time, OCR correction,
and location-ranking rules with visible non-LLM disclosure. US-009 adds
`MenuBarExtra` and bounded in-memory clipboard intake. US-010 adds minimized
SQLite draft persistence, schema migration, reopen/delete behavior, and no
image/full-OCR storage. US-011 adds provider-bounded reminders, local duplicate
warnings, explicit-only MapKit candidates, default-off AES-GCM screenshot
history, and scoped Clear All deletion.

Fresh combined proof on 2026-07-14: the macOS suite passes all 86 tests; the
FastAPI suite passes 16 tests; the benchmark package passes 9 tests; and the
production Local Only runner scores all 100 generated fixtures with zero
critical wrong values and about 137 ms median latency. A separate two-case
macOS UI smoke target proves the app-owned status item, clipboard-to-review
flow, and isolated local draft persistence across relaunch with no Calendar
write. Native inspection shows the deterministic Local Only disclosure and
default-off encrypted screenshot setting. The generated corpus remains
synthetic-only; licensed real-world Local Only/Accuracy reports, direct notch
drag/deletion smoke, live MapKit candidates, and team-signed Data Protection
Keychain reuse remain open platform or user-owned proofs.
