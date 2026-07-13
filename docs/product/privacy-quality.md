# Privacy, Safety, And Quality

## Data Handling

- Delete raw screenshots by default after successful extraction.
- Keep local drafts secure and allow users to delete history.
- Do not log image bytes, full OCR text, OAuth tokens, or private event content.
- Disclose when images or OCR text are sent to cloud OCR or AI providers.
- Local-only mode must prevent cloud calls and explain reduced accuracy.
- Accuracy Mode is opt-in at import time and discloses that the image and OCR
  are sent through the SnapCal service to Google Gemini.
- The local service binds to `127.0.0.1` by default, keeps the Gemini key in its
  environment, requests `store=false`, and does not log or persist request
  bodies.
- Failed extraction asks whether to retain the image for retry.
- Screenshot history is opt-in and local-first.

Retention and deletion are product behavior, not cleanup conveniences. Any
implementation story that persists images, provider payloads, OCR text, or
calendar credentials is high-risk and requires explicit storage, encryption,
retention, and deletion proof.

## Benchmark Contract

The initial corpus contains at least 100 screenshots:

- at least 50 Vietnamese or Vietnamese-English;
- at least 30 English;
- at least 20 noisy, low-resolution, or decorative-font examples;
- representative Facebook, TikTok, Instagram, university, workshop,
  hackathon, concert, webinar, website, and online-event sources.

Each item has ground-truth title, date, time, location, and language labels.
The repository must store only images with appropriate rights and sanitized
private data. Metrics run separately for Vietnamese and English.

## MVP Targets

| Metric | Target |
| --- | ---: |
| Vietnamese title accuracy | >= 85% |
| Vietnamese date accuracy | >= 85% |
| Vietnamese time accuracy | >= 80% |
| English title accuracy | >= 90% |
| English date accuracy | >= 90% |
| English time accuracy | >= 85% |
| Critical wrong date/time rate | <= 3% |
| Median extraction latency | <= 10 seconds |
| Calendar creation after OAuth | >= 95% |

## Regression Rules

- Every benchmark image yields a valid draft or a clear failure reason.
- No date may be invented without evidence.
- Every critical field carries evidence.
- No event may be created without confirmation.
- Prompt, OCR-engine, parser, or normalization changes run the benchmark.
- Wrong critical values count more severely than missing values.

## Operational Metrics

Track screenshot-to-preview success, preview-to-create conversion, manual
corrections per event, import-to-created latency, duplicate-warning accuracy,
correction rate by field, ambiguity detection, and critical-field error rate.
Production logs must use counts/identifiers and redacted metadata rather than
raw screenshot or OCR content.
