# SnapCal Architecture

## Current State

The repository contains a macOS 14 SwiftUI menu-bar app, XCTest target, a
versioned benchmark package, and a FastAPI modular monolith. Local Only keeps
extraction on-device. During development, Accuracy Mode can use the preserved
loopback `/v1` contract. The production `/v2` contract accepts a bounded
multipart JPEG plus layout-aware Apple Vision OCR, authenticates an invited
SnapCal device session, atomically reserves quota in PostgreSQL, and calls
OpenRouter with strict structured output from
`google/gemini-3.1-flash-lite`. Minimized draft metadata persists in owner-only
SQLite; full OCR and screenshots are excluded. Optional screenshot history is
default-off and uses an AES-GCM vault whose key is in the macOS Keychain.
Google desktop OAuth with PKCE uses the same loopback service for secret-bearing
token exchange and keeps Calendar REST creation behind explicit confirmation.
Refresh-token storage is signature-aware: team-signed builds use Data Protection
Keychain and ad-hoc development builds use the local login Keychain.
The default macOS target uses Apple Development signing for local work and a
separate Developer ID Release configuration for team `HKUD5AT6V6` under
`com.hkud5at6v6.snapcal`, with an explicit Keychain access group. The
login-Keychain path remains a fallback for deliberately ad-hoc builds. Sparkle
is Release-only and fail-closed until a real HTTPS appcast and EdDSA public key
are supplied.

The repository now defines the production service, Alembic schema, Cloud Run
container, Terraform, CI/CD, release automation, and operations runbook. It
does not claim that external GCP, Neon, Paddle, Google, OpenRouter, DNS, or
Apple resources have been provisioned. The checked-in 100-image corpus remains
generated regression data, not a licensed real-world accuracy corpus; the
licensed benchmark is deferred from the paid-beta release gate.

Extraction returns one to ten ordered drafts. The shared model reviews one
selected draft at a time, stores sibling Calendar lifecycle independently, and
requires a separate confirmation and provider call for every event.

If resumed, real-world benchmark acceptance uses an external manifest-v2 corpus. Private
non-redistributable images are forbidden from repository-owned directories;
each row carries benchmark/cloud authorization, expected ambiguity labels, and
independent critical-field review. The normal `/v1/extract` response is schema
version 2 with an `events` array; the macOS client retains version-1 response
compatibility. A benchmark-only endpoint is registered only in explicit
benchmark mode, preflights a dedicated OpenRouter key limit no greater than $5,
resolves actual request cost, and maintains serialized process-local
accounting.

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
  -> typed one-or-more event-draft result
  -> one-at-a-time editable review plus minimized local draft persistence
  -> reminder suggestions, local duplicate warnings, and optional explicit
     MapKit place candidates
  -> per-event explicit confirmation state machine
  -> Google desktop OAuth (system browser + loopback callback + PKCE)
  -> loopback FastAPI token broker -> Google OAuth token endpoint
  -> Google Calendar REST events.insert
```

FastAPI and OpenRouter structured extraction are now implemented for local
development. Google Cloud Vision OCR fallback and Google Places/Geocoding
remain deferred target choices.

## Production Accuracy Boundary

```text
macOS Accuracy request
  -> Google identity plus rotating SnapCal device session
  -> multipart JPEG and bounded OCR metadata
  -> reserve transaction: entitlement + invite + quota + limits + idempotency
  -> one same-model OpenRouter request with provider fallback
  -> validate one-to-ten non-empty event proposals
  -> finalize transaction: consume one screenshot unit or release reservation
  -> return plaintext once and retain only a device-sealed retry envelope
  -> expire the envelope after 15 minutes
```

Paddle's signed, deduplicated webhooks own the local subscription cache.
Browser redirects and locally cached UI state never grant Accuracy access. The
successful extraction hot path uses exactly two database transactions and
never queries Paddle or OpenRouter for entitlement. A screenshot consumes one
unit even when it contains multiple events; failure and Local Only fallback
consume none.

The backend never creates Calendar events. Calendar access and refresh tokens
remain in the app's Keychain. A production client sends a refresh token only
transiently through the authenticated `/v2/auth/google/token` broker; the
backend forwards it to Google without persistence. The macOS client continues
to perform one Google Calendar call only after explicit confirmation for that
event.

## Calendar Write Boundary

```text
reviewed EventDraft
  -> pure validation/mapping
  -> awaitingConfirmation (zero provider calls)
  -> explicit user confirmation
  -> authorize or refresh through development loopback or authenticated hosted token broker
  -> POST primary calendar event
  -> success receipt or recoverable failure with draft preserved
```

The app embeds only the public desktop OAuth client ID. It never reads or
bundles the downloaded credential JSON or client secret. FastAPI reads that
JSON from an explicit ignored path or a mounted production secret and adds the
secret only when forwarding a token request to Google. Development uses
`/v1/google-oauth/token`; configured production builds use authenticated
`/v2/auth/google/token` and never target the loopback helper. The system browser
handles Google sign-in; a short-lived `127.0.0.1` listener receives the
callback. The requested scope is limited to creating events in calendars the
user owns.

## Product Boundaries

```text
surfaces
  macOS app | iOS extension/app | Android app
        |
        v
application
  import image | extract event(s) | review selected draft | create one event | manage history
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
  -> Accuracy Mode sends bounded JPEG + OCR to loopback `/v1` in development
     or authenticated hosted `/v2` in production
  -> FastAPI calls OpenRouter Chat Completions with a strict JSON Schema
  -> strict versioned one-to-ten proposal validation and local/cloud disagreement checks
  -> normalization and deterministic consistency checks
  -> confidence and ambiguity rules
  -> ordered typed drafts
  -> mandatory one-at-a-time review and per-event confirmation
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
- PostgreSQL owns invited-beta identity, device sessions, plan configuration,
  lean subscription state, atomic quota, idempotency, redacted audit metadata,
  and a client-encrypted 15-minute retry envelope. It never stores screenshots,
  OCR text, prompts, plaintext event fields, Google tokens, or provider keys.
- SQLAlchemy 2 async uses the Neon pooled endpoint with a maximum four-connection
  pool per application instance. Alembic runs as a one-off deployment job; the
  application never migrates production during startup.
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
5. PostgreSQL-backed contract tests for session rotation, Paddle ordering,
   idempotency, quota concurrency, retry expiry, and 50-user provider-fake load.
6. A bounded 20-request live calibration for cost and latency before checkout;
   this is operational validation, not training or an accuracy benchmark.
7. End-to-end proof that no calendar write occurs before user confirmation.

## Remaining Decisions

- Selection and acquisition of the SnapCal-owned domain.
- Completion of live GCP, Neon, Paddle, Google OAuth, OpenRouter, DNS, Developer
  ID, notarization, and Sparkle-key activation by an authorized operator.
- Public-launch timing after Google OAuth verification and beta evidence.
- Whether measured latency requires one minimum Cloud Run instance, disabling
  Neon scale-to-zero, or eventually adding a cache. The default remains no.
- Real-world benchmark licensing and sanitation if accuracy claims are resumed;
  it is not a paid-beta blocker.
