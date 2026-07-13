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
| SAFE-05 | Raw screenshot is deleted by default after success | persistence integration and platform filesystem proof |
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
provider calls while confirmation makes exactly one. The macOS target builds
and all 22 tests pass. Live browser consent, loopback callback, Keychain, and one
confirmed Calendar event remain a user-driven platform/E2E proof; deletion,
cloud isolation, and benchmark gates remain unimplemented.
