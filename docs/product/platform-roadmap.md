# Platforms And Delivery Roadmap

## Platform Input Contracts

### macOS

The first production target is a SwiftUI menu-bar utility. Phase 1 starts with
manual import; Phase 3 adds `MenuBarExtra`, clipboard intake, recent drafts, and
an AppKit-backed floating top-center drop zone that expands during drag.

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
| 2 | OCR, parsing, confidence, and benchmark reliability | measurable language-separated quality and safe ambiguity behavior |
| 3 | macOS menu-bar and notch-style drop zone | drag/drop, clipboard, review, and local draft history work |
| 4 | Trust hardening | reminders, locations, duplicates, privacy, and deletion are proven |
| 5 | Mobile share flows | iOS and Android receive images and reuse review/calendar behavior |
| 6 | Personalization and automation | preferences, local-only mode, and draft-safe shortcuts work |

## Build Priority

1. Extraction correctness.
2. Review safety.
3. macOS drop-zone UX.
4. Mobile surfaces.
5. Automation.

## Scope Rule

Only the selected phase/story enters implementation. Candidate future work may
appear in the backlog, but folders, dependencies, schemas, APIs, or fake tests
must not be scaffolded until their story is accepted.
