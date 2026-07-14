# Screenshot Intake And Extraction

## Accepted Inputs

MVP image formats are PNG, JPG/JPEG, and HEIC.

- macOS: manual file import plus a top-center notch-style file drop zone;
  clipboard and menu-bar intake remain later slices.
- iOS: Share Extension and in-app image picker.
- Android: `ACTION_SEND` share target and in-app image picker.

Multiple images are not an MVP batch: process the first valid image and inform
the user. A corrupt or unsupported image must fail validation before any cloud
provider call or draft creation.

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
  -> reviewable event draft
```

The extraction boundary must return a typed result: either a draft, a clear
`No event detected` outcome, or a structured failure. It must not return an
unvalidated model payload to the client.

## Modes

### Local Only

Use Apple Vision OCR, deterministic layout-aware extraction, normalization,
and review without sending the image or OCR off-device. This is the default.

### Accuracy Mode

The user explicitly opts in before import. Send a bounded image plus local OCR
and normalized layout boxes to the loopback extraction service. OpenRouter routes
the request to `google/gemini-3.1-flash-lite`, which proposes a strict
evidence-bearing event. If it is unavailable or invalid,
fall back visibly to the deterministic local candidate. Cloud OCR is not part
of this slice.

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
- Provider output is untrusted boundary data and must be parsed before entering
  application or domain layers.
- Provider names, prompts, thresholds, and retries belong in configuration and
  infrastructure, not in normalization rules or UI state.

## Required Behavior

- Preserve Vietnamese diacritics and mixed-language text when recognized.
- Use image layout plus OCR evidence for decorative poster typography.
- Trigger fallback when local evidence is insufficient.
- Mark disagreements on date, time, or location as ambiguities.
- Never invent a date when the image contains no date evidence.
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
