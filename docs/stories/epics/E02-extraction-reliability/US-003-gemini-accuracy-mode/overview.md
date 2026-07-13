# US-003 Overview

## Current Behavior

SnapCal sends Apple Vision text lines to a deterministic parser. It discards OCR
layout boxes, selects the first eligible line as the title, requires date and
time to share parser-friendly lines, and cannot interpret a decorative
multi-day poster such as Agentic AI Build Week.

## Target Behavior

The import screen offers local-only and opt-in Accuracy modes. Accuracy Mode
sends the poster plus layout-aware local OCR to a loopback extraction proxy.
Gemini 2.5 Flash returns a strict proposal that is validated into the existing
evidence-bearing draft. Provider failure falls back visibly to local behavior.

## Affected Users

- macOS users importing decorative Vietnamese, English, or mixed-language event
  posters.

## Affected Product Docs

- `docs/product/extraction.md`
- `docs/product/event-draft.md`
- `docs/product/privacy-quality.md`
- `docs/ARCHITECTURE.md`
- `docs/TEST_MATRIX.md`

## Non-Goals

- Google Cloud Vision OCR fallback.
- Production hosting, billing, quotas, or provider SLA.
- A 100-image accuracy claim or prompt optimization benchmark.
- Automatic calendar creation or removal of mandatory review.
