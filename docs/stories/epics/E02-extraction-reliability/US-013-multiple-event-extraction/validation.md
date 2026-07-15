# US-013 Validation

## Proof Strategy

Prove multi-event detection with deterministic Vietnamese and English OCR
fixtures, strict provider schema tests, application-state tests, and fake
Calendar scheduling. No live Google Calendar event or paid provider request is
part of automated verification.

## Test Plan

| Layer | Cases |
| --- | --- |
| Unit | Two independently dated numbered blocks produce two ordered drafts; ordinary numbered text stays one draft; no clock time is invented; v1 and v2 client decoding |
| Integration | Local and Accuracy success; provider multi-event response; fallback; per-draft persistence; per-position duplicate identity |
| E2E | Supplied Vietnamese screenshot reaches `Event 1 of 2`; user can review both; each fake Calendar write requires its own confirmation |
| Platform | macOS build/tests; Python service tests; review navigation accessibility identifiers |
| Performance | One OCR pass and one Accuracy request per screenshot; maximum 10 proposals |
| Logs/Audit | Static scan and tests keep image, OCR, provider response, token, and event content out of logs |

## Fixtures

- `/Users/hieu/Desktop/Screenshot 2026-07-15 at 09.24.13.png` as the
  user-supplied visual reference.
- Deterministic OCR lines for training bài 1 on 19/07/2026 and training bài 2
  on 16/07/2026.
- Version-2 provider response containing two valid events.
- Empty, over-limit, malformed-member, and version-1 compatibility responses.

## Commands

```bash
python3 -m pytest services/extraction-api/tests -q
xcodebuild -project SnapCal.xcodeproj -scheme SnapCal \
  -destination 'platform=macOS' -derivedDataPath .build/DerivedData \
  CODE_SIGNING_ALLOWED=NO test
```

## Acceptance Evidence

- `python3 -m pytest services/extraction-api/tests -q`: passed 2026-07-15;
  27 tests, including schema-version-2 multiple-event responses, strict
  one-to-ten provider arrays, and empty-array rejection.
- `xcodebuild ... CODE_SIGNING_ALLOWED=NO test`: passed 2026-07-15; 100 tests
  passed and one environment-dependent Data Protection Keychain test skipped.
- The deterministic supplied-notice OCR fixture produces ordered all-day drafts
  for training bài 1 on 19/07/2026 and training bài 2 on 16/07/2026, with no
  invented clock time.
- The application-state Calendar spy proves zero writes after extraction, one
  write after the first explicit confirmation, zero additional writes after
  navigating, and a second write only after the second explicit confirmation.
- `PYTHONPATH=packages/benchmark python3 -m pytest packages/benchmark/tests -q`:
  passed 45 tests. `scripts/run-local-benchmark.sh` passed all 100 generated
  fixtures with zero critical wrong values after the parser change.
- No live OpenRouter request or Google Calendar event was used for automated
  proof.
