# US-007 Validation

## Proof Strategy

Use fixed capture times and `Asia/Ho_Chi_Minh` to prove every semantic rule.
Negative cases ensure uncertain OCR and competing critical values remain
missing or ambiguous rather than silently corrected.

## Test Plan

| Layer | Cases |
| --- | --- |
| Unit | Tomorrow/today; weekday context/conflict; show-start preference; deadline ranking; `20:OO` confidence gate; specific location ranking |
| Integration | Local Only model path makes zero cloud calls and preserves evidence/ambiguity state |
| E2E | Synthetic semantic benchmark fixtures produce a redacted Local Only report |
| Platform | Import disclosure clearly identifies deterministic limitations |
| Performance | Local median extraction latency remains below 10 seconds |
| Logs/Audit | No OCR, image, event content, or credentials added to logs |

## Fixtures

- Vietnamese and English relative-date lines.
- Door-time plus event-start line.
- Registration deadline plus event-date lines.
- Weekday/date agreement and conflict.
- High- and low-confidence `20:OO` lines.
- Generic source label plus specific venue.

## Commands

```bash
xcodebuild -project SnapCal.xcodeproj -scheme SnapCal \
  -destination 'platform=macOS' -derivedDataPath .build/DerivedData \
  CODE_SIGNING_ALLOWED=NO test
scripts/run-local-benchmark.sh
```

## Acceptance Evidence

- Twelve `LocalEventExtractorTests` cover the named deterministic semantic
  rules and negative cases with fixed capture time/timezone evidence.
- `SnapCalModelTests.testLocalOnlyNeverCallsCloudExtractor` proves the Local
  Only application path makes zero cloud calls.
- Native inspection shows Local Only explicitly described as Apple Vision OCR
  plus deterministic rules, not a language model.
- The production-source Local Only runner completed all 100 generated fixtures
  with zero critical wrong values and about 137 ms median latency. This is
  synthetic regression evidence only.
