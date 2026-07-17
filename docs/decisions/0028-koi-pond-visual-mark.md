# 0028 Koi Pond Visual Mark

Date: 2026-07-17

## Status

Accepted

## Context

The current abstract orbit/calendar mark does not match the supplied visual
reference, which centers an irregular dark teal pond with cream koi, fine
concentric ripples, and a vermilion sun. The user requested the same
composition while the app must remain native, scalable, accessible, and free of
third-party asset redistribution.

## Decision

- Replace the shared orbit/calendar mark with a procedural `KoiPondMark`
  rendered from SwiftUI shapes and Canvas.
- Preserve the reference's composition and palette without copying its pixels,
  watermark, typography, or source artwork.
- Use dynamic appearance-aware colors and keep decorative layers hidden from
  VoiceOver and hit testing.
- Replace the existing import/processing/error mark callers without changing
  extraction, privacy, retention, notch geometry, review, or Calendar behavior.

## Alternatives Considered

1. Bundle the supplied crop — rejected because it is reference artwork, not an
   app-owned asset.
2. Keep the orbit mark — rejected because it fails the requested visual match.
3. Add a remote image dependency — rejected because it adds network and
   availability risk to a local visual.

## Consequences

Positive:

- The central mark now directly communicates the requested koi/pond aesthetic.
- Vector rendering scales across compact, wide, light, dark, and high-contrast
  appearances without adding bundle weight.
- Existing trust and interaction boundaries remain unchanged.

Tradeoffs:

- More vector path code must be maintained than the previous generic calendar
  icon.
- Exact source-art texture is approximated procedurally rather than copied.

## Follow-Up

- Recheck contrast and visual balance on light and dark macOS appearances before
  signed release.
