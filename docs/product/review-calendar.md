# Review And Calendar Creation

## Review Contract

The review screen is mandatory. It shows editable title, start date/time or
all-day selection, end time/duration, calendar, location, description,
reminders, confidence warnings, inference markers, and source evidence.

Create Event is disabled when title or date is missing, or when time is missing
without an all-day selection. Missing location does not block creation but must
remain visibly incomplete. A user edit overrides the extracted proposal.

Closing review preserves a draft unless the user explicitly discards it.

When extraction returns multiple drafts, review shows `Event N of M` and lets
the user move through the ordered drafts while no confirmation or Calendar
operation is active. Edits, reminders, duplicate warnings, screenshot preview,
and Calendar lifecycle belong to the selected draft. Every event requires its
own confirmation dialog; there is no `Create All` action.

## Google Calendar Boundary

Calendar writes use a provider adapter around Google Calendar `events.insert`.
The domain and review UI must not depend directly on Google SDK types.

| SnapCal field | Google Calendar field |
| --- | --- |
| title | `summary` |
| location | `location` |
| description and source note | `description` |
| timed start/end | `start.dateTime` / `end.dateTime` |
| all-day start/end | `start.date` / `end.date` |
| reminder choices | `reminders` |

OAuth begins only as part of user-confirmed creation. Cancellation or provider
failure preserves the draft and does not report success. Successful creation
stores the returned provider event identity and calendar link when available.

For multiple-event imports, one confirmation authorizes exactly one
`events.insert` request for the selected draft. Navigating to another draft
does not carry confirmation forward and cannot call the provider.

The native app owns PKCE, state validation, the system-browser callback, access
tokens, refresh tokens, and the confirmed Calendar write. Its bounded token
exchange request goes to the loopback SnapCal service, which reads the installed
OAuth credential JSON from an explicit ignored environment path and adds the
client secret only to Google's token endpoint request. No credential JSON or
client secret is copied into source or the app bundle. Broker configuration,
client mismatch, and provider rejection are separate redacted recoverable
errors.

The refresh token is the only persisted OAuth credential. SnapCal selects its
Keychain backend from the running code signature: Apple team-signed builds use
Data Protection Keychain, while ad-hoc local builds use the user's encrypted
login Keychain. Reads check both stores during a signing transition, successful
saves remove a stale alternate copy, and Disconnect deletes both. Access tokens
remain memory-only and no token value enters logs or UI state.

## Reminder Rules

- Generic: 1 day and 1 hour before.
- Online: 30 minutes and 5 minutes before.
- Workshop/seminar: 1 day and 2 hours before.
- Same-day: 1 hour and 15 minutes before, excluding reminders in the past.
- All-day: 1 day before in the morning.

Google reminder limits are a provider validation concern; the review must block
an invalid override count before submission. SnapCal currently supports popup
and email reminder values in the domain, exposes popup choices in review,
validates zero through 40,320 minutes, and maps at most five reviewed overrides
into the Calendar request. Learning a user's default reminder preferences
remains Phase 6.

## Location Rules

Location may be a full address, venue, district/city, online, hybrid, or
unknown. Preserve raw text when resolution fails. Multiple map candidates need
user choice. An inferred place is visibly inferred. Online meeting information
belongs in the description while the location is presented as Online.

Place lookup is never automatic. The user explicitly chooses Find with Apple
Maps after seeing that the query is sent to Apple Maps. Up to five candidates
are returned; selecting one becomes a user edit. Search failure preserves the
original location and does not block an otherwise valid event.

## Duplicate Warnings

MVP signals are screenshot hash, title/date/time, title/date/location, recent
drafts, and recently created SnapCal events. Duplicate warnings are overridable
and never silently suppress creation. Reading broader calendar history is a
later explicit permission.

Current detection is local-only: exact screenshot fingerprint and normalized
title/start matches are high-confidence warnings; same title/day/location is a
soft warning. Warning override still enters the normal separate Calendar
confirmation state, so it never creates an event directly.

Sibling drafts use different deterministic per-position fingerprints. This
prevents two legitimate events from the same screenshot from being classified
as the same screenshot while preserving repeat-import detection per position.

## State Machine

```text
draft -> reviewed -> creating -> created
  |         |           |
  |         |           +-> failed -> reviewed -> retry
  |         +-> draft
  +-> discarded
```

Only the `reviewed -> creating` transition may call the calendar provider.
