# Screenshot Intake And Extraction

## Accepted Inputs

MVP image formats are PNG, JPG/JPEG, and HEIC.

- macOS: manual file import, top-center notch-style file drop zone, menu-bar
  utility, and in-memory clipboard import.
- iOS: Share Extension and in-app image picker.
- Android: `ACTION_SEND` share target and in-app image picker.

Multiple images are not an MVP batch: process the first valid image and inform
the user. A corrupt or unsupported image must fail validation before any cloud
provider call or draft creation. Clipboard intake accepts native PNG, JPEG,
HEIC, or TIFF pasteboard representations, converts when necessary in memory,
and creates no temporary screenshot file.

## Pipeline

```text
image validation and metadata
  -> orientation/crop/compression preprocessing
  -> local OCR
  -> OCR quality assessment
  -> optional cloud OCR fallback
  -> vision-language extraction using image plus OCR text
  -> Vietnamese-English normalization
  -> date/time/timezone and location parsing
  -> field evidence, confidence, and ambiguity assembly
  -> one or more reviewable event drafts
```

The extraction boundary must return a typed result: either an ordered,
non-empty collection of one to ten drafts, a clear `No event detected` outcome,
or a structured failure. It must not return an unvalidated model payload to the
client. One screenshot may contain multiple events even though multiple input
images are not processed as a batch.

## Modes

### Local Only

Use Apple Vision OCR, deterministic layout-aware extraction, normalization,
and review without sending the image or OCR off-device. This is the default.
Local Only is not a language model: it uses bounded Vietnamese-English rules
for common date, time, title, and location cues and may miss broader semantic
context. The import screen must state that limitation and recommend explicit
Accuracy Mode opt-in when the wording or layout is complex. Local Only splits
numbered blocks only when at least two blocks each carry independent date
evidence; otherwise it preserves the existing single-draft fallback.

### Accuracy Mode

The user explicitly opts in before import. In production, send a metadata-free
JPEG of at most 4 MiB plus at most 150 visual-order OCR lines and 20,000
characters to the authenticated `/v2` service. The longest image edge is at
most 2,048 pixels and smaller images are not enlarged. The existing loopback
`/v1` contract remains for development and calibration. OpenRouter routes
the request to `google/gemini-3.1-flash-lite`, which proposes one or more strict
evidence-bearing events in source order. If it is unavailable or invalid, fall
back visibly to the deterministic local candidates without consuming quota.
Cloud OCR is not part of this slice.

## Provider Policy

- Apple Vision is the preferred local OCR pre-pass on macOS/iOS.
- Cloud OCR is a replaceable port; Google Cloud Vision is the initial candidate
  because Vietnamese is a required language.
- OpenRouter Chat Completions is the initial vision-language adapter behind a
  replaceable port and strict versioned schema; the default model is
  `google/gemini-3.1-flash-lite` and neither is a domain dependency.
- The OpenRouter key belongs only to the FastAPI process environment. The macOS app
  sends no provider credential and accepts only HTTPS or loopback HTTP service
  addresses.
- The app-facing `/v1/extract` response schema version 2 contains an `events`
  array of one to ten proposals and no benchmark accounting. The macOS client
  still decodes the version-1 single `event` response during local rolling
  upgrades. Explicit benchmark mode adds a separate loopback-only endpoint
  that verifies a provider-limited key and enforces cumulative cost.
- Provider output is untrusted boundary data and must be parsed before entering
  application or domain layers.
- Provider names, prompts, thresholds, and retries belong in configuration and
  infrastructure, not in normalization rules or UI state.
- Production Accuracy requires a SnapCal bearer session and an idempotency key.
  One screenshot reserves one unit even when it yields several drafts. Only a
  valid non-empty cloud result consumes that unit.

## Required Behavior

- Preserve Vietnamese diacritics and mixed-language text when recognized.
- Use image layout plus OCR evidence for decorative poster typography.
- Trigger fallback when local evidence is insufficient.
- Mark disagreements on date, time, or location as ambiguities.
- Never invent a date when the image contains no date evidence.
- Never treat vague day-part words such as `tối` or `evening` as clock times.
- Preserve source order when one image yields multiple independently
  actionable events.
- Keep capture time because relative phrases such as `ngày mai`, `tối nay`,
  `tomorrow`, and `tonight` depend on it.

## Initial Failure Taxonomy

- `unsupported_image`
- `corrupt_image`
- `no_event_detected`
- `insufficient_event_evidence`
- `provider_unavailable`
- `provider_rejected_input`
- `invalid_provider_output`
- `extraction_timeout`

Failures must not expose secrets, raw image bytes, or full OCR text in logs.
