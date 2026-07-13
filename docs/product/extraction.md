# Screenshot Intake And Extraction

## Accepted Inputs

MVP image formats are PNG, JPG/JPEG, and HEIC.

- macOS: manual file import first; later drag/drop, clipboard, and menu bar.
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

### Fast Mode

Use local OCR, vision-language extraction, normalization, and review when the
image is clear and required evidence is strong.

### Accuracy Mode

Add cloud OCR when local evidence is short, fragmented, low-confidence,
diacritic-damaged, or visually complex. Provider fallback must be visible to
the user because image or text may leave the device.

## Provider Policy

- Apple Vision is the preferred local OCR pre-pass on macOS/iOS.
- Cloud OCR is a replaceable port; Google Cloud Vision is the initial candidate
  because Vietnamese is a required language.
- Vision-language extraction is a replaceable port with a strict event-draft
  schema. OpenAI and Gemini are candidates, not domain dependencies.
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
