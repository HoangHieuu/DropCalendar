# US-007 Overview

## Status

implemented and synthetic-regression-proven

## Previous Behavior

Local Only runs Apple Vision OCR followed by deterministic rules. It handles
basic numeric and English month dates, but users can reasonably mistake it for
a semantic language model. It also prefers the first date, time, or location
marker even when text identifies a registration deadline, door time, or generic
source label.

## Implemented Behavior

Local Only is explicitly described as OCR plus deterministic rules with limited
semantic understanding. It handles common Vietnamese-English intent cues such
as tomorrow/today, event-start versus door time, registration deadlines versus
event dates, weekday conflicts, high-confidence `OO` time corrections, and
specific locations versus generic platform labels. Unresolved conflicts remain
visible ambiguities and Local Only never calls a cloud service.

## Affected Users

- Privacy-conscious macOS users selecting Local Only.
- Vietnamese, English, and mixed-language users reviewing event drafts.

## Affected Product Docs

- `docs/product/extraction.md`
- `docs/product/event-draft.md`
- `docs/product/privacy-quality.md`
- `docs/TEST_MATRIX.md`

## Non-Goals

- Claiming that deterministic Local Only is an LLM.
- Silently falling back to OpenRouter.
- Resolving every natural-language or poster-layout ambiguity.
- Removing mandatory review or evidence requirements.
