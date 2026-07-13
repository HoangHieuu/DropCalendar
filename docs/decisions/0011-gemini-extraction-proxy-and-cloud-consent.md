# 0011 Gemini Extraction Proxy And Cloud Consent

Date: 2026-07-13

## Status

Accepted

## Context

Decorative posters preserve visual hierarchy and date ranges that line-only OCR
cannot reliably interpret. SnapCal needs multimodal extraction, but a distributed
macOS application cannot keep a Gemini credential secret and screenshots may
contain private content.

## Decision

- Add Gemini 2.5 Flash as a replaceable multimodal extraction provider behind a
  FastAPI service boundary.
- Bind the development service to `127.0.0.1` and keep `GEMINI_API_KEY` only in
  the service environment. Never bundle it in the macOS application or source.
- Send the original poster representation, local OCR text, OCR confidence and
  normalized layout boxes together in one stateless request.
- Use a versioned request/response contract and Gemini structured output. Parse
  and validate every provider field before constructing an `EventDraft`.
- Make Accuracy Mode an explicit opt-in on the import screen with visible cloud
  disclosure. Local-only mode is the default and must make zero cloud calls.
- Fall back to local extraction with a visible ambiguity when the proxy or
  provider is unavailable. Never replace date evidence silently when local and
  model results disagree.
- Treat all-day end dates in the review UI as inclusive; convert to Google's
  exclusive end date only at the Calendar adapter boundary.

## Alternatives Considered

1. Embed a Gemini API key in the macOS app. Rejected because client binaries
   cannot protect provider secrets.
2. Replace Apple Vision with Gemini. Rejected because local OCR supplies useful
   evidence, supports local-only mode, and enables disagreement checks.
3. Call Vertex AI directly from the macOS app using broad Google Cloud scopes.
   Rejected because it expands authorization and still creates client-side
   credential and quota-control concerns.
4. Default to cloud processing. Rejected because screenshots may contain
   private data and decision 0009 requires meaningful disclosure and local-only
   behavior.

## Consequences

Positive:

- The model can use font size, spatial grouping, icons, and multi-line ranges.
- Provider credentials remain outside distributable client code.
- The cloud path is replaceable and independently contract-tested.

Tradeoffs:

- Local development requires running a small service and supplying a separate
  Gemini authorization key.
- Accuracy Mode sends screenshot content and OCR text to Google after opt-in.
- Live accuracy and cost claims require a licensed benchmark and real provider
  credentials.

## Follow-Up

- Move the loopback service to managed hosting with Secret Manager before
  distributing SnapCal outside local development.
- Re-evaluate the default model using the benchmark rather than model branding.
