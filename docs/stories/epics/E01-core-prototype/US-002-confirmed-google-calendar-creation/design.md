# US-002 Design

## Domain Model

- `CalendarCreationReceipt`: provider event ID and validated HTTPS calendar link.
- `CalendarCreationState`: idle, awaiting confirmation, authorizing, creating,
  created, or failed.
- Calendar request validation requires non-empty title, start, end after start,
  and explicit all-day/timed mapping.

## Application Flow

1. Review button calls `requestCalendarCreation`; no provider is called.
2. Confirmation cancel returns to review.
3. Confirmation accept is the only transition allowed to call the scheduler.
4. Scheduler obtains a valid access token, authorizing interactively only when
   no refresh token is usable; secret-bearing token exchange is delegated to
   the configured loopback SnapCal service.
5. Calendar adapter calls `events.insert` for calendar ID `primary`.
6. Success exposes the returned link; cancellation or failure preserves draft.
7. Disconnect deletes the Keychain refresh token and in-memory access token.

## Interface Contract

- OAuth authorization endpoint: `https://accounts.google.com/o/oauth2/v2/auth`.
- OAuth token endpoint: `https://oauth2.googleapis.com/token`.
- Local token-broker endpoint: `POST
  http://127.0.0.1:8765/v1/google-oauth/token`.
- Calendar endpoint: `POST
  https://www.googleapis.com/calendar/v3/calendars/primary/events`.
- Authorization scope:
  `https://www.googleapis.com/auth/calendar.events.owned`.
- Provider responses are decoded into small local DTOs; tokens and provider
  bodies never become UI state or logs.

## Data Model

No database or draft persistence is added. Only the Google refresh token is
persisted in Keychain using the app bundle ID and OAuth client ID as stable
service/account identifiers. Access tokens remain in memory.

## UI / Platform Impact

- Review gains editable end time, connection status, Create Event, confirmation,
  authorizing/creating progress, success link, retry, and disconnect controls.
- The app sandbox adds outgoing HTTPS and incoming localhost listener access.
- OAuth opens the user's system browser; SnapCal never embeds Google login.
- Broker configuration and client mismatch have distinct recoverable UI errors.

## Observability

No raw OCR, event fields, OAuth codes, tokens, client secret, or provider body is
logged. User-facing errors use stable redacted categories.

## Alternatives Considered

1. Google SDK dependency: deferred for this bounded adapter.
2. Service account: rejected for personal user calendars.
3. Pre-connect account button: rejected because the contract starts OAuth only
   from confirmed creation.
