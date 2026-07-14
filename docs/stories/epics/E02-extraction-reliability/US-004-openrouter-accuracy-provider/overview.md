# US-004 Overview

## Current Behavior

Accuracy Mode calls Google Gemini directly through the `google-genai` SDK and
requires `GEMINI_API_KEY`. The user has selected OpenRouter instead, so the
existing service ignores their `OPENROUTER_API_KEY` and cannot start from the
root `.env` configuration.

## Target Behavior

The loopback extraction service loads the root `.env`, authenticates only with
`OPENROUTER_API_KEY`, and sends the poster plus layout-aware OCR to OpenRouter's
multimodal Chat Completions API. The default model is
`google/gemini-3.1-flash-lite`. Strict structured-output validation, local-only
isolation, visible fallback, and mandatory Calendar review remain unchanged.

## Affected Users

- macOS users who opt into Accuracy Mode and provide an OpenRouter key.

## Affected Product Docs

- `docs/product/extraction.md`
- `docs/product/privacy-quality.md`
- `docs/ARCHITECTURE.md`
- `docs/TEST_MATRIX.md`
- `README.md`

## Non-Goals

- Production hosting or multi-user key management.
- OpenRouter account creation, billing, or automatic key provisioning.
- Benchmark-wide model accuracy claims.
- Changing Local Only or Google Calendar authorization.
