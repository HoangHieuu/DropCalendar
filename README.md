# SnapCal

SnapCal turns an event screenshot into a reviewed Google Calendar event.
It is designed first for Vietnamese and English event posts, posters, stories,
reels, websites, and community announcements where copying date, time, and
location manually is slow or error-prone.

```text
Screenshot
  -> OCR and visual extraction
  -> Vietnamese-English normalization
  -> date, time, timezone, and location validation
  -> mandatory user review
  -> Google Calendar event
```

## Current State

The first macOS vertical slice and its guarded Google Calendar boundary are
implemented. `SnapCal.xcodeproj` contains a SwiftUI app and XCTest target that
validate a selected PNG, JPEG, or HEIC, run Vietnamese-English Apple Vision OCR
locally, derive an evidence-bearing typed draft, present an editable review,
and create a Google Calendar event only after a separate confirmation dialog.
Images and drafts remain in memory. The Google refresh token is the only
persisted value and is stored in macOS Keychain.

The root `SPEC.md` is the supplied source snapshot. The smaller files under
`docs/product/`, the active story packets, executable proof, and accepted
decisions are the living contract for ongoing work.

## Open And Run

Open `SnapCal.xcodeproj` in Xcode, select the `SnapCal` scheme and **My Mac**, then
press **Run** (`Command-R`). The deployment target is macOS 14.0. No package
installation or API key is required. A Google account listed as an OAuth test
user is required for the live Calendar flow. The downloaded desktop credential
JSON stays outside this repository; the app embeds only its public OAuth client
ID and never embeds or reads the client secret.

Run the complete test target from Terminal with:

```bash
xcodebuild -project SnapCal.xcodeproj -scheme SnapCal \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test
```

## Product Rules That Must Not Drift

- Never create a calendar event without explicit user confirmation.
- Treat date, start time, timezone, and travel-critical location as critical
  fields; uncertainty is safer than a silent guess.
- Preserve source evidence and confidence for every critical extracted field.
- Support Vietnamese, English, and mixed-language screenshots from the first
  extraction slice.
- Delete raw screenshots by default after successful extraction.
- Keep platform input native: macOS drag/drop or clipboard, iOS Share
  Extension, and Android Share Target.

## Build Order

1. Prove manual screenshot intake, structured extraction, review, and calendar
   creation.
2. Improve Vietnamese-English OCR, normalization, and benchmark reliability.
3. Add the macOS menu-bar and top-center drop-zone experience.
4. Harden reminders, locations, duplicates, and privacy controls.
5. Add iOS and Android share flows.
6. Add preferences, local-only mode, and App Intents/Shortcuts.

## Repository Map

- `SnapCal.xcodeproj` — macOS app and test project; open this file in Xcode.
- `apps/macos/SnapCal/` — app, application, domain, feature, and infrastructure
  sources.
- `apps/macos/SnapCalTests/` — validation, extraction, OAuth, Calendar mapping,
  provider contract, and confirmation-state tests.
- `SPEC.md` — original product-spec snapshot.
- `docs/product/overview.md` — goals, users, boundaries, and success definition.
- `docs/product/extraction.md` — image intake, OCR, fallback, and extraction.
- `docs/product/event-draft.md` — canonical draft, evidence, confidence, and
  normalization rules.
- `docs/product/review-calendar.md` — review, reminders, duplicates, and Google
  Calendar creation.
- `docs/product/privacy-quality.md` — retention, safety, benchmark, and metrics.
- `docs/product/platform-roadmap.md` — macOS, mobile, and phased delivery.
- `docs/ARCHITECTURE.md` — target boundaries and dependency direction.
- `docs/stories/backlog.md` — candidate epics; only selected work becomes an
  active story.
- `docs/TEST_MATRIX.md` — proof vocabulary and critical safety gates.
- `docs/DEVELOPMENT_CAPABILITIES.md` — installed plugins, skills, tools, and
  project-specific usage policy.

## Working With Harness

For a change request, bootstrap and inspect the active matrix before editing:

```bash
scripts/bootstrap-harness.sh
scripts/bin/harness-cli query matrix --active --summary
scripts/bin/harness-cli query tools --summary
```

Read `AGENTS.md`, `docs/FEATURE_INTAKE.md`, and `docs/CONTEXT_RULES.md` for the
full collaboration contract. Answer/review/diagnosis requests stay read-only
and do not initialize or mutate Harness state.

## What Is Deliberately Not Here Yet

There is no backend, database schema, benchmark corpus, mobile app, or CI
workflow. The live Google OAuth/create path still requires one user-driven
platform proof because SnapCal must never consent or create an event on the
user's behalf.
