# Review And Calendar Creation

## Review Contract

The review screen is mandatory. It shows editable title, start date/time or
all-day selection, end time/duration, calendar, location, description,
reminders, confidence warnings, inference markers, and source evidence.

Create Event is disabled when title or date is missing, or when time is missing
without an all-day selection. Missing location does not block creation but must
remain visibly incomplete. A user edit overrides the extracted proposal.

Closing review preserves a draft unless the user explicitly discards it.

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

## Reminder Rules

- Generic: 1 day and 1 hour before.
- Online: 30 minutes and 5 minutes before.
- Workshop/seminar: 1 day and 2 hours before.
- Same-day: 1 hour and 15 minutes before, excluding reminders in the past.
- All-day: 1 day before in the morning.

Google reminder limits are a provider validation concern; the review must block
an invalid override count before submission.

## Location Rules

Location may be a full address, venue, district/city, online, hybrid, or
unknown. Preserve raw text when resolution fails. Multiple map candidates need
user choice. An inferred place is visibly inferred. Online meeting information
belongs in the description while the location is presented as Online.

## Duplicate Warnings

MVP signals are screenshot hash, title/date/time, title/date/location, recent
drafts, and recently created SnapCal events. Duplicate warnings are overridable
and never silently suppress creation. Reading broader calendar history is a
later explicit permission.

## State Machine

```text
draft -> reviewed -> creating -> created
  |         |           |
  |         |           +-> failed -> reviewed -> retry
  |         +-> draft
  +-> discarded
```

Only the `reviewed -> creating` transition may call the calendar provider.
