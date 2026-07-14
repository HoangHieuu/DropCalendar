# Platforms And Delivery Roadmap

## Platform Input Contracts

### macOS

The first production target is a SwiftUI menu-bar utility. Manual import is
implemented. US-005 adds the first AppKit-backed floating top-center drop zone:
it stays compact across spaces, expands on hover or drag, and forwards the first
supported image into the existing review flow. Phase 3 now also provides a
shared-model `MenuBarExtra`, in-memory clipboard intake, and recent SQLite-backed
drafts that reopen into review.

### iOS

Use a Share Extension and in-app image picker. Do not imitate a draggable
Dynamic Island. App Intents/Shortcuts are a later automation surface and may
create or open drafts, but MVP auto-create remains prohibited.

### Android

Use the system share target through `ACTION_SEND` plus an in-app picker. Android
should reuse the same provider-neutral extraction contract, not duplicate core
normalization logic.

## Phase Plan

| Phase | Outcome | Exit signal |
| --- | --- | --- |
| 1 | Manual screenshot -> draft -> review -> Google Calendar prototype | Vietnamese and English happy paths work; no write without review |
| 2 | OCR, parsing, confidence, and benchmark reliability | In progress: deterministic rules and synthetic regression pass; licensed real-world dual-mode benchmark remains |
| 3 | macOS menu-bar and notch-style drop zone | Implemented and code-proven: drag/drop, clipboard, review, and local draft history |
| 4 | Trust hardening | Implemented and code-proven: reminders, explicit location lookup, local duplicates, encrypted opt-in screenshots, and deletion |
| 5 | Mobile share flows | iOS and Android receive images and reuse review/calendar behavior |
| 6 | Personalization and automation | preferences, local-only mode, and draft-safe shortcuts work |

## Build Priority

1. Extraction correctness.
2. Review safety.
3. macOS drop-zone UX.
4. Mobile surfaces.
5. Automation.

## Current Phase

Implementation has reached the end of Phase 4, while the Phase 2 measurement
gate remains open. Phase 3 and Phase 4 code do not convert synthetic fixtures
into a real-world accuracy claim. The next release-blocking work is to replace
or supplement the synthetic corpus with licensed, sanitized event screenshots,
run both production modes, harden failures found by that report, and repeat the
native menu-bar/relaunch/deletion smoke checklist.

## Scope Rule

Only the selected phase/story enters implementation. Candidate future work may
appear in the backlog, but folders, dependencies, schemas, APIs, or fake tests
must not be scaffolded until their story is accepted.

## On-Device Semantic Gate

Decision 0016 reserves a separate Local Semantic Mode using Apple's Foundation
Models framework when a compatible SDK and runtime are available. The current
toolchain cannot compile that framework. Do not raise the macOS 14 deployment
floor or bundle a third-party language model without new benchmark and product
evidence. An unavailable local model falls back only to deterministic Local
Only; cloud Accuracy Mode always requires separate explicit opt-in.
