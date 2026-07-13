# US-003 Design

## Domain Model

- `ExtractionMode`: local-only or Accuracy Mode.
- `RecognizedTextLine` retains normalized layout bounds.
- The cloud contract proposes evidence-bearing title, temporal range, location,
  description, all-day state, confidence, inference, and ambiguities.
- Provider output is not an `EventDraft` until strict date, range, evidence, and
  confidence validation succeeds.

## Application Flow

1. User selects an extraction mode before choosing a screenshot.
2. Image validation and Apple Vision OCR always run locally.
3. Local-only mode calls only the deterministic extractor.
4. Accuracy Mode encodes a bounded JPEG and sends it with OCR/layout metadata to
   the configured loopback proxy.
5. The client parses a versioned response into an evidence-bearing draft.
6. Unavailable/invalid cloud responses fall back to the local draft and add a
   visible ambiguity.
7. Review and explicit Calendar confirmation remain unchanged.

## Interface Contract

- `GET /health` returns service/model readiness without secret material.
- `POST /v1/extract` accepts contract version, JPEG/PNG base64, capture time,
  timezone, locale, and OCR lines with confidence/layout.
- The response returns contract version, model identifier, a validated event
  proposal, and structured ambiguities.
- Errors use stable categories and never echo image bytes, OCR text, prompts, or
  provider bodies.

## Data Model

No database or screenshot persistence is introduced. Requests are stateless.
The proxy receives image/OCR content in memory for one extraction and does not
store it. The provider key is read from `GEMINI_API_KEY` only.

## UI / Platform Impact

- Import gains a Local Only / Accuracy Mode picker and cloud disclosure.
- Processing text reflects the selected mode.
- Review identifies Gemini, on-device, or local-fallback extraction.
- Existing `@Observable` application state owns mode and extraction notice;
  networking stays outside SwiftUI views.

## Observability

Allowed: request ID, model, duration, outcome, error category, byte count, OCR
line count. Prohibited: image/base64, OCR strings, extracted event content,
prompt, API key, and raw provider responses.

## Alternatives Considered

1. Direct Gemini calls from SwiftUI: rejected for secret exposure and weak test
   isolation.
2. Gemini-only extraction: rejected because local evidence and offline behavior
   are product requirements.
3. Silent cloud fallback: rejected because cloud processing must be visible.
