# Platforms And Delivery Roadmap

## Platform Input Contracts

### macOS

The first production target is a SwiftUI menu-bar utility. Manual import is
implemented. US-005 adds the first AppKit-backed floating top-center drop zone:
it stays compact across spaces, expands on hover or drag, and forwards the first
supported image into the existing review flow. Phase 3 now also provides a
shared-model `MenuBarExtra`, in-memory clipboard intake, and recent SQLite-backed
drafts that reopen into review.

US-018 adds a responsive full-window shell and a shared original
Japanese-print-inspired visual system across import, review, history, settings,
the menu-bar popover, and the visible notch panel. It changes presentation only:
the existing review handoff, accessibility identifiers, privacy disclosures,
drop geometry, and explicit Calendar confirmation remain the contract.

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
| 2 | OCR, parsing, confidence, and benchmark reliability | In progress: deterministic rules and synthetic regression pass; Local Semantic provenance-aware and licensed real-world two-mode benchmarks remain |
| 3 | macOS menu-bar and notch-style drop zone | Implemented and code-proven: drag/drop, clipboard, review, and local draft history |
| 4 | Trust hardening | Implemented and code-proven: reminders, explicit location lookup, local duplicates, encrypted opt-in screenshots, and deletion |
| 5 | Release and monetization | invited paid beta has hosted auth, Paddle entitlements, quota, privacy retention, direct signed updates, and bounded operations |
| 6 | Mobile share flows | iOS and Android receive images and reuse review/calendar behavior |
| 7 | Personalization and automation | preferences, Local Semantic defaults, and draft-safe shortcuts work |

## Build Priority

1. Extraction correctness.
2. Review safety.
3. macOS drop-zone UX.
4. Paid beta and direct release.
5. Mobile surfaces.
6. Automation.

## Current Phase

Implementation is in Phase 5, Release and Monetization. The hosted `/v2`
boundary, database schema, account/paywall UI, webhook-owned entitlements,
quota accounting, encrypted retry retention, infrastructure as code, CI/CD,
Sparkle integration, and notarized-release automation are implemented. Live
activation still requires the user-owned domain, provider projects/secrets,
Paddle catalog and seller approval, Google verification configuration,
Developer ID/notary credentials, and the bounded 20-request calibration.

The Phase 2 licensed real-world measurement gate remains open for future public
quality claims but is explicitly deferred from the 50-user invited beta.

## Scope Rule

Only the selected phase/story enters implementation. Candidate future work may
appear in the backlog, but folders, dependencies, schemas, APIs, or fake tests
must not be scaffolded until their story is accepted.

## On-Device Semantic Gate

Decision 0026 exposes one Local Semantic choice backed by Apple's Foundation
Models framework when its compiled adapter, runtime, locale, and system model
are available. Apple Vision OCR plus deterministic parsing remains the safety
baseline on every supported Mac. An unavailable, unsupported, failed, or invalid
semantic request keeps Local Semantic selected and visibly uses that baseline.
It never routes to cloud processing; Accuracy Mode always requires a separate
explicit opt-in.

Keep the macOS 14 deployment floor and compile the Foundation Models adapter
conditionally. Public semantic-quality claims and production release activation
remain gated by separate Vietnamese, English, and mixed-language benchmark
evidence. The benchmark provenance schema needed to distinguish Foundation
Models from deterministic fallback is still open.
