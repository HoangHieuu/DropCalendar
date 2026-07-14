# SnapCal Architecture

## Current State

The repository contains a macOS 14 SwiftUI app, XCTest target, and a loopback
FastAPI extraction service. Local Only keeps extraction on-device. Opt-in
Accuracy Mode sends a bounded JPEG plus layout-aware Apple Vision OCR to the
local service, which owns the OpenRouter credential and validates strict
structured output from `google/gemini-3.1-flash-lite`. Drafts remain in memory.
Google desktop OAuth with PKCE uses the same loopback service for secret-bearing
token exchange, stores its refresh token in Keychain when the build has a usable
signed identity, and keeps Calendar REST creation behind explicit confirmation.
There is no production deployment, database, or benchmark corpus.

The macOS surface owns one shared `SnapCalModel`. A non-activating AppKit
`NSPanel` hosts the SwiftUI notch drop target and forwards selected file URLs
into that model; it does not own extraction or Calendar state.

## First Vertical Slice

The initial implementation target is macOS-first:

```text
SwiftUI manual image import and review
  -> Apple Vision local OCR
  -> Local Only deterministic extraction
     or opt-in loopback FastAPI -> OpenRouter -> Gemini 3.1 Flash Lite
  -> typed event-draft result
  -> in-memory editable review
  -> explicit confirmation state machine
  -> Google desktop OAuth (system browser + loopback callback + PKCE)
  -> loopback FastAPI token broker -> Google OAuth token endpoint
  -> Google Calendar REST events.insert
```

FastAPI and OpenRouter structured extraction are now implemented for local
development. Google Cloud Vision OCR fallback and Google Places/Geocoding
remain deferred target choices.

## Calendar Write Boundary

```text
reviewed EventDraft
  -> pure validation/mapping
  -> awaitingConfirmation (zero provider calls)
  -> explicit user confirmation
  -> authorize or refresh through bounded loopback token broker
  -> POST primary calendar event
  -> success receipt or recoverable failure with draft preserved
```

The app embeds only the public desktop OAuth client ID. It never reads or
bundles the downloaded credential JSON or client secret. The local FastAPI
service reads that JSON from an explicit ignored path and adds the secret only
when forwarding a token request to Google. The system browser handles Google
sign-in; a short-lived `127.0.0.1` listener receives the callback. The requested
scope is limited to creating events in calendars the user owns.

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
  -> deterministic local candidate with layout boxes
  -> Local Only returns the local candidate, or
  -> Accuracy Mode sends image + OCR to 127.0.0.1 proxy
  -> proxy calls OpenRouter Chat Completions with a strict JSON Schema
  -> strict versioned proposal validation and local/cloud disagreement checks
  -> normalization and deterministic consistency checks
  -> confidence and ambiguity rules
  -> typed draft
  -> mandatory review
```

Cloud OCR remains future infrastructure. The OpenRouter adapter enters through
the inward-facing cloud-extraction protocol and its model remains configurable.

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
- Keychain stores OAuth credentials on Apple platforms. An unsigned local build
  may use the current access token even when refresh-token persistence is
  unavailable; it must request consent again after that in-memory token expires
  or the app restarts.
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

- Production hosting and secret-management boundary if Accuracy Mode moves
  beyond the current loopback development service.
- Versioned event-draft schema transport.
- Benchmark asset licensing and private-data sanitization.
- Whether any server-owned metadata requires PostgreSQL; default is no.
