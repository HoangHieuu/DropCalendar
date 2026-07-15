# US-012 In-Memory Notch Image Drops

## Status

Implemented and automated-proof complete; a fresh macOS floating screenshot
drag remains in the manual platform smoke checklist.

## Current Behavior

The macOS notch accepts only local file URLs whose names end in PNG, JPG,
JPEG, or HEIC. macOS floating screenshot thumbnails and some image previews
offer image data or temporary file representations instead, so the notch
reports an unsupported drop before image validation or extraction begins.

## Target Behavior

The notch accepts one supported Finder image, floating screenshot thumbnail,
or compatible image-data representation. Temporary and data representations
are read into memory, pass through the existing image validator and extraction
pipeline, and open the mandatory editable review without creating a Calendar
event.

## Affected Users

- macOS users dragging screenshots directly from the system screenshot
  thumbnail, Finder, or an image preview.

## Affected Product Docs

- `docs/product/extraction.md`
- `docs/product/platform-roadmap.md`
- `docs/product/privacy-quality.md`

## Non-Goals

- Batch image import.
- PDF, video, text, or remote-URL drops.
- Persisting app-owned raw screenshot copies.
- Changing OCR, semantic extraction, cloud consent, or Calendar confirmation.
