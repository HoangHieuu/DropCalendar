# 0027 Responsive Washi Interface

Date: 2026-07-17

## Status

Accepted

## Context

SnapCal's main ready-state `HStack` retained its intrinsic width in a
full-screen window, leaving a large trailing strip outside the composed
interface. The user also requested a complete redesign based on a supplied
Japanese-style Pinterest reference, including the visible notch drop panel.
The reference contains third-party artwork and a watermark, while SnapCal's
trust disclosures, native accessibility, and explicit Calendar confirmation
must remain unchanged.

## Decision

- Make every main-window phase claim all available width and height.
- Keep content widths readable while the shared canvas fills the complete
  window.
- Use an original dynamic visual system inspired by Japanese print composition:
  warm paper, deep teal ink, vermilion accents, serif display type, and
  procedural orbit, ripple, and wave motifs.
- Do not bundle, trace, copy, or redistribute the supplied reference image,
  watermark, typography, fish, or botanical artwork.
- Keep important controls native and preserve every trust disclosure,
  accessibility identifier, keyboard path, and separate per-event Calendar
  confirmation.
- Style only the software panel around and below the physical display notch;
  the app cannot render inside the camera cutout.
- Preserve the notch panel's tested size, top-center anchoring, drop semantics,
  `.mainMenu` level, and shared-model handoff.
- Hide decorative artwork from accessibility and honor Reduce Motion.

## Alternatives Considered

1. Apply only `maxWidth: .infinity`. Rejected because it fixes the defect but
   not the requested full-app visual redesign.
2. Ship the supplied image as a background. Rejected because it is a
   watermarked visual reference rather than an app-owned redistributable asset,
   and it would not adapt safely across sizes and appearances.
3. Replace native fields and dialogs with custom controls. Rejected because
   this would add accessibility and confirmation risk without product value.

## Consequences

Positive:

- Full-screen and resized windows have intentional edge-to-edge composition.
- Import, review, history, settings, menu-bar, and notch surfaces read as one
  product.
- Product trust boundaries remain visually prominent and mechanically
  unchanged.

Tradeoffs:

- Procedural decoration adds SwiftUI rendering code that needs compact and wide
  platform inspection.
- The hardware camera cutout itself cannot receive the themed treatment.

## Follow-Up

- Keep a maximized-window regression in the macOS UI smoke.
- Recheck contrast, keyboard navigation, VoiceOver ordering, and Reduce Motion
  before a signed release.
