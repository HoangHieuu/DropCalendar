# US-008 Overview

## Status

implementation in progress; the adapter typechecks, live generation awaits
Apple Intelligence, full Xcode proof awaits license acceptance, and the
provenance-aware benchmark schema remains open

## Current Behavior

At intake, the app exposed Local Only and Accuracy Mode. Local Only used Apple
Vision OCR plus deterministic rules, Accuracy Mode used an explicitly opted-in
OpenRouter model, and there was no compiled on-device language-model adapter.

## Target Behavior

The app exposes exactly two choices: Local Semantic and Accuracy Mode. Local
Semantic attempts Apple's on-device system language model when the compiled
framework, runtime, locale, and model state allow it. Otherwise
it remains selected and transparently uses deterministic Apple Vision OCR plus
local parsing. No Local Semantic path may call cloud services, and every result
still enters the existing evidence validation, editable review, and explicit
Calendar confirmation boundary.

## Affected Users

- Privacy-conscious macOS users who need more semantic understanding than the
  deterministic fallback alone can provide.

## Affected Product Docs

- `docs/product/extraction.md`
- `docs/product/privacy-quality.md`
- `docs/product/overview.md`
- `docs/product/billing-release.md`
- `docs/product/event-draft.md`
- `docs/product/review-calendar.md`
- `docs/product/platform-roadmap.md`
- `README.md`
- `docs/ARCHITECTURE.md`
- `docs/TEST_MATRIX.md`
- `docs/stories/backlog.md`
- `packages/benchmark/` provenance contract

## Non-Goals

- Pretending Foundation Models generated a proposal before Apple Intelligence
  is enabled and live runtime proof passes.
- Raising the deployment target or shipping an unbenchmarked bundled model.
- Adding an automatic cloud fallback.
- Improving characters that Apple Vision OCR did not recognize.
