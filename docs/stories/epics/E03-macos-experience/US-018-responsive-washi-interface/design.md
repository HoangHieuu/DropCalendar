# Design

## Domain Model

No domain model changes. `EventDraft`, extraction provenance, Calendar state,
and local-history lifecycle remain authoritative.

## Application Flow

No command or state-machine changes. Manual, clipboard, menu-bar, and notch
imports still enter the shared `SnapCalModel`, extraction still ends in
editable review, and Calendar creation still requires a distinct explicit
confirmation for the selected event.

## Interface Contract

Existing accessibility identifiers and user-visible trust disclosures remain
stable. The ready shell becomes fully flexible; wide review layouts may arrange
the same panels into two columns while compact layouts preserve their safe
reading order.

## Data Model

No schema, migration, persistence, retention, or deletion changes.

## UI / Platform Impact

- Add a shared dynamic palette and reusable SwiftUI paper/card/motif
  components.
- Make every `ContentView` phase fill the available window.
- Keep the primary import pane flexible and size the history rail
  responsively.
- Use a readable bounded editorial composition over a full-bleed canvas.
- Arrange review as a primary form and supporting inspector on wide windows,
  with a single-column fallback on compact windows.
- Restyle recent drafts, processing, errors, settings, menu-bar content, and
  the visible notch panel with the same system.
- Keep the notch's tested collapsed and expanded geometry and `.mainMenu`
  level.
- Hide decorative shapes from accessibility and honor Reduce Motion.

## Observability

No new product telemetry. Executable build, unit, and UI-smoke output is the
proof surface; no screenshot bytes or private event text enter logs or traces.

## Alternatives Considered

1. Stretch the existing dark layout only. Rejected because it fixes the gap but
   does not satisfy the requested cohesive redesign.
2. Use `ref.jpg` as a background asset. Rejected because the watermarked
   reference is inspiration, not a redistributable product asset, and would
   reduce contrast and adaptability.
3. Rebuild every native form control. Rejected because native controls preserve
   macOS accessibility, keyboard, date, and confirmation behavior.
