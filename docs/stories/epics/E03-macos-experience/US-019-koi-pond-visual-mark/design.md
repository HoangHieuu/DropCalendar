# Design

## Domain Model

No domain model changes. `EventDraft`, extraction provenance, and Calendar
lifecycle remain authoritative.

## Application Flow

No command or state-machine changes. The mark is presentation-only in import,
processing, and error states.

## Interface Contract

Keep the existing `chooseScreenshotButton`, `pasteScreenshotButton`,
`extractionModePicker`, `extractionModeDisclosure`, review, notch, and menu-bar
accessibility identifiers unchanged. Decorative mark layers remain hidden from
the accessibility tree and do not intercept input.

## Data Model

No schema, persistence, retention, or deletion changes.

## UI / Platform Impact

- Add a reusable `KoiPondMark` SwiftUI component.
- Match the reference's pond/sun/koi/ripple composition with dynamic light and
  dark appearance colors.
- Use deterministic vector/canvas drawing so the mark scales cleanly and adds
  no asset or network dependency.
- Keep Reduce Motion behavior unchanged because the mark is static.

## Observability

No new telemetry or logs. The mark contains no screenshot, OCR, or event data.

## Alternatives Considered

1. Bundle the supplied reference crop. Rejected because it is third-party
   reference artwork and would not adapt to appearance, scale, or contrast.
2. Keep the orbit/calendar mark. Rejected because it does not match the
   requested visual direction.
3. Use a remote image or SF Symbol collage. Rejected because it adds a
   dependency and cannot faithfully reproduce the pond composition.
