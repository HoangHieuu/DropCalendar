# SnapCal Architecture

## Current State

The repository contains a macOS 14 SwiftUI menu-bar app, XCTest target, a
versioned benchmark package, and a loopback FastAPI extraction service. Local
Only keeps extraction on-device. Opt-in
Accuracy Mode sends a bounded JPEG plus layout-aware Apple Vision OCR to the
local service, which owns the OpenRouter credential and validates strict
structured output from `google/gemini-3.1-flash-lite`. Minimized draft metadata
persists in owner-only SQLite; full OCR and screenshots are excluded. Optional
screenshot history is default-off and uses an AES-GCM vault whose key is in the
macOS Keychain.
Google desktop OAuth with PKCE uses the same loopback service for secret-bearing
token exchange and keeps Calendar REST creation behind explicit confirmation.
Refresh-token storage is signature-aware: team-signed builds use Data Protection
Keychain and ad-hoc development builds use the local login Keychain.
The default macOS target is now Apple Development signed for team `HKUD5AT6V6`
under `com.hkud5at6v6.snapcal`, with an explicit Keychain access group. The
login-Keychain path remains a fallback for deliberately ad-hoc builds.
There is no production service deployment or server database. The checked-in
100-image corpus is generated regression data, not a licensed real-world
accuracy corpus.

The macOS surface owns one shared `SnapCalModel`. A non-activating AppKit
`NSPanel` hosts the SwiftUI notch drop target and forwards selected file URLs
into that model; `MenuBarExtra`, clipboard intake, recent drafts, settings, and
the main window use the same model and do not own extraction or Calendar state.

## First Vertical Slice

The initial implementation target is macOS-first:

```text
SwiftUI manual image import and review
  -> Apple Vision local OCR
  -> Local Only deterministic extraction
     or opt-in loopback FastAPI -> OpenRouter -> Gemini 3.1 Flash Lite
  -> typed event-draft result
  -> editable review plus minimized local draft persistence
  -> reminder suggestions, local duplicate warnings, and optional explicit
     MapKit place candidates
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

An optional Local Semantic Mode is architecture-approved but toolchain-gated by
decision 0016. The current macOS 15.5 SDK cannot import Apple's Foundation
Models framework, so deterministic Local Only remains the only on-device mode.
A future adapter must preserve macOS 14 compatibility, check system-model
availability, fall back only to deterministic Local Only, and pass separate
benchmark gates before becoming user-visible.

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
- SQLite schema version 2 stores minimized review/lifecycle data and source
  fingerprints, with a transactional version-1 migration. It excludes image
  bytes and the full OCR transcript.
- Keychain stores the OAuth refresh token on Apple platforms. Team-signed builds
  prefer Data Protection Keychain; ad-hoc development builds use the encrypted
  local login Keychain. Reads check the alternate backend during signing
  transitions, and Disconnect deletes both. The default target's application
  identifier and Keychain access group are provisioned from its Apple team and
  bundle identifier. Access tokens remain in memory.
- PostgreSQL is deferred until a server-owned metadata need is proven.
- Screenshot history is disabled by default. If explicitly enabled, app-owned
  image copies use an AES-GCM local vault and a Keychain key. Clear All removes
  draft rows, vault files, and that key; user originals are outside SnapCal's
  deletion scope.
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

## Remaining Decisions

- Production hosting and secret-management boundary if Accuracy Mode moves
  beyond the current loopback development service.
- Versioned event-draft schema transport.
- Real-world benchmark asset licensing and private-data sanitization.
- Whether any server-owned metadata requires PostgreSQL; default is no.
