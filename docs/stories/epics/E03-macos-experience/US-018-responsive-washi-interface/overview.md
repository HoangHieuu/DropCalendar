# US-018 Responsive Washi Interface

## Current Behavior

The ready screen keeps its intrinsic SwiftUI width when the main window enters
full screen. The import pane and fixed-width recent-drafts rail therefore stop
before the trailing window edge and expose an unowned strip of window
background. Import, processing, failure, review, history, settings, menu-bar,
and notch surfaces also use separate generic system styling rather than one
cohesive visual language.

## Target Behavior

Every main-window phase owns the full available window and adapts between
compact and wide layouts. SnapCal uses an original Japanese print-inspired
visual system built from warm paper, deep ink, vermilion accents, serif display
type, and procedural ripple/orbit motifs. The supplied `ref.jpg` is visual
direction only and is not copied into or bundled with the app.

The visible notch panel shares the same visual language while retaining its
existing geometry, drop behavior, window level, and mandatory-review handoff.
The physical camera cutout remains outside the app's drawable area.

## Affected Users

- macOS users importing, reviewing, and managing screenshot-derived drafts.
- Keyboard, VoiceOver, high-contrast, and Reduce Motion users.

## Affected Product Docs

- `docs/product/platform-roadmap.md`
- `docs/product/review-calendar.md`
- `docs/product/privacy-quality.md`

## Non-Goals

- Changing extraction, persistence, retention, billing, OAuth, or Calendar
  behavior.
- Creating an event without the existing per-event confirmation dialog.
- Bundling, tracing, or redistributing the supplied Pinterest reference image.
- Rendering pixels inside the physical Mac camera cutout.
- Replacing native macOS controls where they carry important accessibility or
  platform behavior.
