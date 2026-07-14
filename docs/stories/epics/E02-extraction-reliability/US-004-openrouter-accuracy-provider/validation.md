# US-004 Validation

## Proof Strategy

Use a recording HTTP client and fixed OpenRouter responses to prove exact
authentication boundaries, multimodal input shape, strict response format,
redacted failures, and unchanged client behavior. A live request is allowed only
when a user-owned `.env` key is present; no secret value may enter output.

## Test Plan

| Layer | Cases |
| --- | --- |
| Unit | Configuration validation; response parsing; schema validation |
| Integration | Bearer request shape; image data URL; JSON Schema; status mapping; redaction |
| E2E | Supplied poster through live OpenRouter, only when configured |
| Platform | Xcode build/tests; loopback health; visible OpenRouter source/fallback |
| Performance | 25-second provider timeout and existing 20 MB request bound |
| Logs/Audit | No key, image, OCR, prompt, or provider body in errors/logs |

## Fixtures

- Fixed successful OpenRouter Chat Completions envelope.
- Unauthorized, rate-limited, unavailable, malformed, and schema-invalid
  provider responses.
- Existing Agentic AI Build Week proposal and macOS client fixtures.

## Commands

```bash
python3 -m pytest services/extraction-api/tests -q
xcodebuild -project SnapCal.xcodeproj -scheme SnapCal \
  -destination 'platform=macOS' -derivedDataPath .build/DerivedData \
  CODE_SIGNING_ALLOWED=NO test
```

## Acceptance Evidence

- `.venv/bin/python -m pytest services/extraction-api/tests -q`: 11 passed.
- `xcodebuild -project SnapCal.xcodeproj -scheme SnapCal -destination
  'platform=macOS' -derivedDataPath .build/DerivedData
  CODE_SIGNING_ALLOWED=NO test`: 30 passed; `TEST SUCCEEDED`.
- Recording-provider tests prove Bearer authentication, base64 image input,
  strict JSON Schema, parameter-compatible routing, status mapping, and secret
  redaction without a live provider call.
- `GET http://127.0.0.1:8765/health`: `200 OK`, provider `openrouter`, model
  `google/gemini-3.1-flash-lite`, and `ready: true`; no provider request made.
- 2026-07-14: the user reported that a live, explicitly opted-in Accuracy Mode
  extraction succeeded with their OpenRouter configuration. No key, screenshot,
  OCR text, or private event content was recorded as proof.
- This live success proves provider operability only. Accuracy claims remain
  gated on the versioned Vietnamese-English benchmark.
