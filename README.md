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

The macOS vertical slice, guarded Google Calendar boundary, and opt-in OpenRouter
Accuracy Mode are implemented. `SnapCal.xcodeproj` validates a selected PNG,
JPEG, or HEIC, runs Vietnamese-English Apple Vision OCR, derives an
evidence-bearing typed draft, presents an editable review, and creates a Google
Calendar event only after a separate confirmation dialog. Local Only is the
default and makes no cloud extraction call. Accuracy Mode sends the image and
layout-aware OCR to a loopback FastAPI proxy, which keeps the OpenRouter
credential out of the app and validates strict structured output from
`google/gemini-3.1-flash-lite`. Images and
drafts remain in memory. The Google refresh token is the only persisted value
and is stored in macOS Keychain when the local build has a usable signed
Keychain identity. The same loopback service brokers Google OAuth token
exchange because the installed OAuth credential requires its client secret;
the secret and downloaded credential JSON never enter the app bundle or source.
The macOS app also presents a compact top-center notch-style panel that expands
on hover or drag targeting. Dropping an image there brings the main window
forward and enters the same extraction and mandatory-review flow.

The root `SPEC.md` is the supplied source snapshot. The smaller files under
`docs/product/`, the active story packets, executable proof, and accepted
decisions are the living contract for ongoing work.

## Open And Run

Open `SnapCal.xcodeproj` in Xcode, select the `SnapCal` scheme and **My Mac**, then
press **Run** (`Command-R`). The deployment target is macOS 14.0. Local Only
extraction requires no package installation or API key. A Google account listed
as an OAuth test user is required for the live Calendar flow. Calendar creation
also requires the local service described below. The downloaded desktop
credential JSON stays outside this repository; the app embeds only its public
OAuth client ID and never embeds or reads the client secret.

After launch, move the pointer to the compact `SnapCal` pill at the top-center
of the display or drag a PNG, JPEG, or HEIC screenshot onto it. The panel
expands, accepts the first supported image, and opens the review flow.

Accuracy Mode requires an OpenRouter API key. Do not use the Google Calendar
OAuth JSON for this. Create the local service and private environment file once:

```bash
cp .env.example .env
# Edit .env and replace the OPENROUTER_API_KEY placeholder with your key.
# Set GOOGLE_OAUTH_CREDENTIALS_FILE to the absolute path of the downloaded
# Desktop OAuth JSON kept outside this repository.
python3 -m venv .venv
.venv/bin/python -m pip install -r services/extraction-api/requirements.txt
```

Then start it in a separate Terminal window before selecting Accuracy Mode or
confirming Google Calendar creation:

```bash
scripts/run-extraction-api.sh
```

The service automatically loads the repository-root `.env` and binds only to
`127.0.0.1:8765` by default. The model can be changed with
`OPENROUTER_MODEL`; the default is `google/gemini-3.1-flash-lite`.

Run the complete test target from Terminal with:

```bash
xcodebuild -project SnapCal.xcodeproj -scheme SnapCal \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test

.venv/bin/python -m pip install -r services/extraction-api/requirements-dev.txt
.venv/bin/python -m pytest services/extraction-api/tests -q
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
6. Add preferences and App Intents/Shortcuts.

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

There is no production backend deployment, database schema, benchmark corpus,
mobile app, or CI workflow. Live OpenRouter extraction still requires a funded
user-owned key and one user-driven poster proof. The live Google OAuth/create path also
requires a user-driven platform proof because SnapCal must never consent or
create an event on the user's behalf.
