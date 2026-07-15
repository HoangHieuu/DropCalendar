# 0021 In-Memory macOS Image Drop Boundary

Date: 2026-07-15

## Status

Accepted

## Context

The notch originally accepted only named local image URLs. macOS floating
screenshot thumbnails and some image previews instead provide raw image data
or short-lived file representations. Supporting them requires deciding who
owns temporary data and whether a drop changes retention or review behavior.

## Decision

- SnapCal accepts one local PNG, JPEG, or HEIC file URL or one compatible PNG,
  JPEG, HEIC, or TIFF data/temporary representation from macOS drag providers.
- SnapCal reads temporary provider representations while valid and converts
  them into an in-memory import value. It does not create a new temporary file.
- TIFF exists only as an interoperability input and is converted to PNG in
  memory before the existing validator runs.
- All representations use the same 20 MB, supported-format, non-empty, and
  decodable-image validation boundary before OCR or semantic extraction.
- The drop reuses the normal extraction and mandatory editable review flow.
  It never authorizes a Calendar write and does not change cloud consent.
- Default raw screenshot retention remains off. Optional encrypted screenshot
  history remains separately governed by decision 0018.

## Alternatives Considered

1. Persist provider data in a SnapCal temporary file. Rejected because it adds
   an app-owned private copy without a product need.
2. Require users to save every screenshot to Finder first. Rejected because it
   breaks the intended notch interaction.
3. Accept all public image subtypes without a format allowlist. Rejected so the
   product contract and validation surface stay bounded.

## Consequences

- Native screenshot-thumbnail drops can enter the same review workflow as
  Finder files and clipboard images.
- Temporary provider URLs never escape the loader callback.
- Direct automation of the system floating-thumbnail interaction remains a
  manual platform smoke check, backed by deterministic provider tests.

## Verification

```text
xcodebuild -project SnapCal.xcodeproj -scheme SnapCal -destination 'platform=macOS' -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO -only-testing:SnapCalTests/NotchDropZoneTests -only-testing:SnapCalTests/SnapCalModelTests test
```
