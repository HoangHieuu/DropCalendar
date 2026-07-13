# SnapCal Architecture

## Current State

The repository contains a macOS 14 SwiftUI app and XCTest target. The implemented
boundary keeps extraction local and drafts in memory: native file import,
strict image validation, Apple Vision OCR, deterministic Vietnamese-English
extraction, a typed evidence-bearing draft, and editable review. A narrow
infrastructure boundary now adds Google desktop OAuth with PKCE, device-only
Keychain refresh-token storage, and direct Google Calendar REST creation after
explicit confirmation. There is no backend, database, benchmark corpus, or
deployment configuration.

## First Vertical Slice

The initial implementation target is macOS-first:

```text
SwiftUI manual image import and review
  -> Apple Vision local OCR
  -> deterministic local extraction service boundary
  -> typed event-draft result
  -> in-memory editable review
  -> explicit confirmation state machine
  -> Google desktop OAuth (system browser + loopback callback + PKCE)
  -> Google Calendar REST events.insert
```

The spec recommends FastAPI for the extraction backend, a vision-language
provider with structured output, Google Cloud Vision as OCR fallback, and
Google Places/Geocoding for location candidates. These remain target choices,
not installed dependencies or completed integrations.

## Calendar Write Boundary

```text
reviewed EventDraft
  -> pure validation/mapping
  -> awaitingConfirmation (zero provider calls)
  -> explicit user confirmation
  -> authorize or refresh
  -> POST primary calendar event
  -> success receipt or recoverable failure with draft preserved
```

The app embeds only the public desktop OAuth client ID. It never reads or
bundles the downloaded credential JSON or client secret. The system browser
handles Google sign-in; a short-lived `127.0.0.1` listener receives the callback.
The requested scope is limited to creating events in calendars the user owns.

## Product Boundaries

```text
surfaces
  macOS app | iOS extension/app | Android app
        |
        v
application
  import image | extract event | review draft | create event | manage history
        |
        v
domain
  event draft | evidence | confidence | ambiguity | date/time rules
        ^
        |
infrastructure
  OCR | VLM | calendar | places | SQLite | HTTP | keychain | logging
```

Domain and application layers do not depend on SwiftUI, FastAPI, Google SDKs,
model-provider SDKs, databases, or environment variables. Infrastructure
implements ports defined inward.

## Candidate Repository Shape

The current and candidate shape is created incrementally as stories require it:

```text
apps/
  macos/SnapCal/
  macos/SnapCalTests/
  ios/
  android/
services/
  extraction-api/
packages/
  event-contract/
  benchmark/
docs/
  product/
  stories/
```

Shared packages must earn their existence through at least two real consumers.
Do not force native Swift and backend Python to share source code; share a
versioned schema and fixtures where appropriate.

## Extraction Sequence

```text
untrusted image
  -> validation and metadata
  -> local OCR
  -> deterministic local candidate
  -> normalization and deterministic consistency checks
  -> confidence and ambiguity rules
  -> typed draft
  -> mandatory review
```

Optional cloud OCR and a structured VLM adapter remain future infrastructure;
they must enter through the same inward-facing OCR and extraction protocols.

Models propose fields; deterministic code validates dates, timezones, reminder
limits, and state transitions. Provider confidence is evidence, not authority.

## Parse-First Boundaries

Parse and validate all unknown data at entry:

- dropped, pasted, selected, or shared images;
- OCR and VLM responses;
- Google OAuth and Calendar responses;
- Places/Geocoding candidates;
- SQLite rows and future API payloads;
- environment configuration and secrets;
- mobile extension payloads and deep links.

## Persistence And Secrets

- SQLite stores local draft metadata first.
- Keychain stores OAuth credentials on Apple platforms.
- PostgreSQL is deferred until a server-owned metadata need is proven.
- Object storage is prohibited by default and requires opt-in screenshot
  history plus a retention/deletion design.
- Credentials never enter source control, screenshots, traces, fixtures, or
  application logs.

## Observability

Emit structured operational events with timestamp, level, request/operation ID,
action, duration, outcome, and redacted error class. Do not log raw image data,
full OCR text, provider prompts containing private content, or tokens. Product
retention records and operational logs remain separate concerns.

## Validation Ladder

1. Pure unit tests for Vietnamese-English normalization, date/time/timezone,
   duration, reminders, duplicate signals, and state transitions.
2. Contract tests for provider adapters and strict payload parsing.
3. Integration tests for local persistence and calendar failure/retry behavior.
4. Xcode/Simulator or macOS platform tests for import, review, and UI state.
5. Curated benchmark evaluation for extraction accuracy and latency.
6. End-to-end proof that no calendar write occurs before user confirmation.

## Decisions Required Before Implementation

- Phase 2 extraction provider and server/local boundary, if local extraction is
  not reliable enough against the benchmark.
- Versioned event-draft schema transport.
- Benchmark asset licensing and private-data sanitization.
- Whether any server-owned metadata requires PostgreSQL; default is no.
