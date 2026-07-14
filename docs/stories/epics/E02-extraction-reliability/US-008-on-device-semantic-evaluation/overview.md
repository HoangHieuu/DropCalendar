# US-008 Overview

## Status

decision complete; implementation remains toolchain-gated

## Current Behavior

Local Only uses Apple Vision OCR plus deterministic rules. Accuracy Mode uses an
explicitly opted-in OpenRouter model. There is no on-device language-model mode.

## Target Behavior

The repository records a reproducible toolchain/runtime capability check and an
accepted architecture decision for a separate Local Semantic Mode. The decision
identifies the preferred on-device framework, availability behavior, privacy
boundary, compatibility policy, benchmark gate, and implementation prerequisite.

## Affected Users

- Privacy-conscious macOS users who need more semantic understanding than
  deterministic Local Only can provide.

## Affected Product Docs

- `docs/product/extraction.md`
- `docs/product/platform-roadmap.md`
- `docs/ARCHITECTURE.md`

## Non-Goals

- Pretending the current SDK can compile Foundation Models.
- Raising the deployment target or shipping an unbenchmarked bundled model.
- Adding an automatic cloud fallback.
