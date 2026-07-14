# Privacy, Safety, And Quality

## Data Handling

- Do not retain an app-owned raw screenshot copy by default after extraction.
  User-selected original files are never deleted or changed.
- Keep local drafts secure and allow users to delete history.
- Do not log image bytes, full OCR text, OAuth tokens, or private event content.
- Disclose when images or OCR text are sent to cloud OCR or AI providers.
- Local-only mode must prevent cloud calls and explain reduced accuracy.
- Local Only copy must identify Apple Vision OCR plus deterministic rules and
  must not imply on-device LLM-level semantic understanding.
- Accuracy Mode is opt-in at import time and discloses that the image and OCR
  are sent through the SnapCal service to OpenRouter and its selected model
  provider.
- The local service binds to `127.0.0.1` by default, loads the OpenRouter key
  from its environment, and does not log or persist request bodies.
- Failed extraction keeps no new durable screenshot copy by default.
- Screenshot history is opt-in, local-only, and encrypted at rest with
  AES-GCM. Its 256-bit key is stored in the macOS Keychain; the vault directory
  and files use owner-only permissions.
- Clear All removes SnapCal's local draft rows, app-owned encrypted screenshot
  copies, and the vault key. It does not delete user originals or Google
  Calendar events.

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

The checked-in version-1 corpus currently contains 100 project-generated,
sanitized, redistributable fixtures and supports synthetic regression claims
only. Local Only runs the production Apple Vision and deterministic extractor
sources. Accuracy Mode has a separate production-source runner that requires
an explicit cloud/cost opt-in. Phase 2 real-world accuracy acceptance still
requires a licensed non-synthetic corpus and complete Local Only and Accuracy
reports over that corpus.

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
