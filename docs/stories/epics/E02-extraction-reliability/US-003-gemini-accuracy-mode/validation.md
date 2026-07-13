# US-003 Validation

## Proof Strategy

Prove request/response validation, zero-cloud local mode, provider fallback, and
date/evidence safety with deterministic fakes. Use the supplied poster as a
licensed local fixture for the bounded regression. Treat real Gemini output,
latency, and cost as pending until a user-provided key runs the live path.

## Test Plan

| Layer | Cases |
| --- | --- |
| Unit | Request limits; schema validation; date/time/range rules; all-day exclusive Calendar mapping; layout retention |
| Integration | Local-only zero calls; Accuracy success; provider unavailable fallback; malformed provider output rejection |
| E2E | Supplied poster -> Agentic AI Build Week -> July 8–12 all day -> review |
| Platform | Xcode test/build; loopback proxy health; opt-in disclosure and source banner |
| Performance | Request bounded to 20 MB; provider timeout; latency measured only in live proof |
| Logs/Audit | Static scan excludes key, image/base64, OCR/event content, and provider body logging |

## Fixtures

- `/Users/hieu/Downloads/data/1.jpg` as the user-supplied regression input.
- Fixed OCR layout lines for the poster.
- Valid Gemini proposal for Agentic AI Build Week, July 8–12, 2026, all day.
- Missing-evidence, reversed-range, malformed JSON, unavailable, and timeout
  provider responses.

## Commands

```bash
python3 -m pytest services/extraction-api/tests -q
xcodebuild -project SnapCal.xcodeproj -scheme SnapCal \
  -destination 'platform=macOS' -derivedDataPath .build/DerivedData \
  CODE_SIGNING_ALLOWED=NO test
```

## Acceptance Evidence

- `xcodebuild ... test`: passed 2026-07-13; 30 tests, including layout-aware
  poster parsing, local-only isolation, Accuracy success/fallback, strict client
  parsing, credential-free requests, and inclusive all-day Calendar mapping.
- `.venv/bin/python -m pytest services/extraction-api/tests -q`: passed
  2026-07-13; 5 contract tests.
- Real loopback Uvicorn process: `/health` returned HTTP 200 with
  `model=gemini-2.5-flash` and `ready=false` without a key, as designed.
- Live Gemini response, latency, cost, and supplied-poster E2E remain pending a
  dedicated user-provided Gemini key. No benchmark accuracy claim is made.
