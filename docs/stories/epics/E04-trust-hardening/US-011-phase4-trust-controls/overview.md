# US-011 Phase 4 Trust Controls

## Status

implemented and code-proven; live MapKit candidate selection remains a manual
network/platform smoke check

## Previous Behavior

Review safely edits core fields and requires confirmation, but does not expose
reminder controls, local duplicate warnings, user-initiated place candidates,
or a privacy/history settings surface.

## Implemented Behavior

Review offers safe reminder suggestions and edits, visible local duplicate
warnings with confirmation override, online/location normalization plus
user-initiated MapKit candidates, and privacy controls for default-off encrypted
screenshot history and explicit Clear All deletion.

## Affected Users

- macOS users reviewing and creating events.
- Privacy-conscious users managing local history.

## Affected Product Docs

- `docs/product/event-draft.md`
- `docs/product/review-calendar.md`
- `docs/product/privacy-quality.md`
- `docs/product/platform-roadmap.md`

## Non-Goals

- Reading the user's broader Google Calendar for duplicate detection.
- Automatic location queries or device-location permission.
- Reminder preference learning, which remains Phase 6.
