# US-006 Overview

## Status

in progress: evaluator and synthetic regression corpus implemented; licensed
non-synthetic dual-mode acceptance remains open

## Previous Behavior

SnapCal has focused Swift and FastAPI fixtures, but no licensed 100-image corpus,
versioned ground truth, repeatable evaluator, or language-separated accuracy
report. Local Only semantic limitations and Accuracy Mode improvements therefore
cannot be quantified.

## Implemented And Remaining Behavior

A repository command validates a versioned corpus of at least 100 licensed and
sanitized screenshots, consumes Local Only or Accuracy Mode predictions, and
reports the Phase 2 metrics defined by the product contract. Invalid provenance,
hashes, labels, predictions, or private-data assertions fail closed.

The command and schema are implemented with a 100-image generated corpus. The
production Local Only path is repeatable, and Accuracy Mode has a separate
explicitly cost-gated runner. Both runners accept an external owner-controlled
manifest and output directories; a fail-closed real-world flag rejects the
entire run if any item is synthetic. Because every current checked-in item is
generated, Phase 2 still needs licensed/sanitized non-synthetic assets and
complete reports from both modes before making a real-world accuracy claim.

## Affected Users

- SnapCal users relying on correct Vietnamese, English, or mixed-language event
  extraction.
- Maintainers changing OCR, prompts, models, parsing, or normalization.

## Affected Product Docs

- `docs/product/extraction.md`
- `docs/product/privacy-quality.md`
- `docs/ARCHITECTURE.md`
- `docs/TEST_MATRIX.md`
- `docs/product/platform-roadmap.md`

## Non-Goals

- Claiming production accuracy from synthetic-only fixtures.
- Uploading Local Only benchmark images to a cloud provider.
- Logging raw OCR, prompts, private event text, image bytes, or credentials.
- Selecting an on-device LLM before benchmark evidence exists.
