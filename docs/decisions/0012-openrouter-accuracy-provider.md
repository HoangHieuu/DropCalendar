# 0012 OpenRouter Accuracy Provider

Date: 2026-07-13

## Status

Accepted

## Context

The first Accuracy Mode adapter called Google Gemini directly, but the user has
chosen OpenRouter and already prepared an `OPENROUTER_API_KEY`. Keeping the old
adapter would leave their configuration unused and the loopback service offline.

## Decision

- Replace the direct `google-genai` adapter with an HTTP OpenRouter adapter.
- Use `https://openrouter.ai/api/v1/chat/completions` by default and
  `google/gemini-3.1-flash-lite` as the configurable default model.
- Load `OPENROUTER_API_KEY` from the root `.env` into the loopback service only.
- Send the private local poster as a base64 data URL plus OCR/layout evidence
  only after explicit Accuracy Mode opt-in.
- Require OpenRouter strict JSON Schema output and continue Pydantic and Swift
  validation before constructing an `EventDraft`.
- Preserve Local Only as the default, visible provider/fallback disclosure,
  stateless request handling, and mandatory Calendar confirmation.

## Alternatives Considered

1. Continue using a Google Gemini key: rejected by the user.
2. Call OpenRouter directly from Swift: rejected because it exposes the API key.
3. Use JSON mode without a schema: rejected because it weakens provider output
   guarantees.

## Consequences

Positive:

- The user's existing OpenRouter account and selected model become usable.
- The provider credential remains outside the distributable app.
- Provider routing stays behind the same replaceable proxy contract.

Tradeoffs:

- Screenshot and OCR content are disclosed to OpenRouter and its routed model
  provider after opt-in.
- Live output, price, and latency depend on OpenRouter routing and user credits.

## Follow-Up

- Run the supplied poster through the live provider and record redacted proof.
- Select future models from benchmark evidence rather than branding alone.
