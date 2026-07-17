# US-019 Koi Pond Visual Mark

## Current Behavior

The shared visual system still uses an abstract orbit/calendar mark for the
import hero and processing/error states. The supplied target reference shows a
dark teal circular pond, cream koi silhouettes, concentric water rings, and a
vermilion sun.

## Target Behavior

Replace the orbit/calendar mark with a native, scalable koi-pond mark that
matches the supplied reference composition: cream field, irregular dark teal
pond, vermilion sun, cream koi, and fine ripples. The mark must render from
SwiftUI shapes/canvas rather than a copied or bundled third-party image.

The mark remains decorative and must not change extraction, review, privacy,
retention, notch geometry, or Calendar-confirmation behavior.

## Affected Users

- macOS users importing or waiting for screenshot extraction.
- VoiceOver, high-contrast, and Reduce Motion users.

## Affected Product Docs

- `docs/product/platform-roadmap.md`
- `docs/product/privacy-quality.md`
- `docs/TEST_MATRIX.md`

## Non-Goals

- Changing Local Semantic, Accuracy, OCR, or event-draft behavior.
- Adding a remote image, third-party asset, or new package.
- Rendering inside the physical camera cutout.
- Removing the existing review or explicit Calendar confirmation gates.
