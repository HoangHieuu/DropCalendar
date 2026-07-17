# Privacy, Safety, And Quality

## Data Handling

- Do not retain an app-owned raw screenshot copy by default after extraction.
  User-selected original files are never deleted or changed.
- Keep local drafts secure and allow users to delete history.
- Do not log image bytes, full OCR text, OAuth tokens, or private event content.
- Disclose when images or OCR text are sent to cloud OCR or AI providers.
- Local Semantic must make zero app-initiated account, backend, billing,
  database, OpenRouter, or other cloud calls.
- Local Semantic remains selected when its system model is unavailable or fails,
  but import and review copy must truthfully identify whether the Apple
  on-device model or deterministic fallback produced the draft.
- Deterministic fallback copy must not imply that a language model ran.
- Accuracy Mode is opt-in at import time and discloses that the image and OCR
  are sent through the SnapCal service to OpenRouter and its selected model
  provider.
- The local service binds to `127.0.0.1` by default, loads the OpenRouter key
  from its environment, and does not log or persist request bodies.
- The hosted service never persists screenshots, submitted OCR, prompts,
  plaintext events, Google tokens, or provider credentials. It stores only
  redacted request/cost/latency/quota metadata and a device-encrypted retry
  envelope that expires after 15 minutes.
- Each installation owns a Curve25519 retry key in Keychain. The server seals
  the structured response to its public key and cannot decrypt the stored
  envelope.
- Redacted request and audit metadata is aggregated and removed after 90 days.
  Exact expiry tasks are backed by an idempotent daily sweep.
- Failed extraction keeps no new durable screenshot copy by default.
- Screenshot history is opt-in, local-only, and encrypted at rest with
  AES-GCM. Its 256-bit key is stored in the macOS Keychain; the vault directory
  and files use owner-only permissions.
- Clear All removes SnapCal's local draft rows, app-owned encrypted screenshot
  copies, and the vault key. It does not delete user originals or Google
  Calendar events.

The responsive visual redesign is presentation-only. Its procedural paper,
ink, and motif layers are decorative, hidden from accessibility, and do not
capture, persist, transmit, or log screenshot/OCR/event content. The supplied
reference image is visual direction only and is not bundled.

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
only. The existing legacy Local Only runner exercises the production Apple
Vision and deterministic extractor sources and remains the deterministic
fallback baseline. Accuracy Mode has a separate production-source runner that
requires an explicit cloud/cost opt-in. Licensed real-world acceptance still
requires a non-synthetic corpus and complete Local Semantic and Accuracy
reports. Local Semantic reports must separate Foundation Models from
deterministic-fallback execution. The benchmark prediction schema does not yet
carry that provenance, so semantic acceptance remains open. This work is
deferred and is not an invited paid-beta release blocker because current
deterministic and Accuracy quality was accepted. It remains mandatory before a
public semantic-quality claim or a major model/provider/prompt/parser change
that could invalidate accepted quality.

Real-world acceptance uses manifest version 2 in an owner-controlled directory
outside Git. Each item must be non-synthetic, hash-verified, sanitized,
benchmark-authorized, independently reviewed, and, for Accuracy Mode,
explicitly authorized for OpenRouter. Private benchmark permission may be used
without public redistribution rights. Accuracy evaluation starts a dedicated
loopback process, verifies a provider-side key limit no greater than $5,
accounts actual request cost, and aborts if cost cannot be verified. Reports
contain only redacted aggregate cost and quality metadata.

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

- Every benchmark image yields one or more valid drafts or a clear failure
  reason.
- No date may be invented without evidence.
- Vague day-part words do not become invented clock times.
- Every critical field carries evidence.
- No event may be created without confirmation.
- Prompt, OCR-engine, parser, or normalization changes run the benchmark.
- Wrong critical values count more severely than missing values.

## Operational Metrics

Track screenshot-to-preview success, extracted-event count,
preview-to-create conversion, manual corrections per event, import-to-created
latency, duplicate-warning accuracy,
correction rate by field, ambiguity detection, and critical-field error rate.
Production logs must use counts/identifiers and redacted metadata rather than
raw screenshot or OCR content.

## Paid Beta Cost And Latency Gates

- Run exactly 20 existing sanitized fixtures before enabling live checkout.
- Mean valid-extraction provider cost must be at most US$0.005; p95 at most
  US$0.01; projected 100-call mean at most US$0.50.
- Accuracy median must be under five seconds and p95 under ten seconds.
- Warm backend overhead must be p95 under 500 ms and each quota transaction
  p95 under 100 ms.
- The dedicated OpenRouter key has a US$25 monthly hard limit. Recorded spend
  blocks new reservations at the same ceiling and alerts at 70%, 85%, and
  100%.
