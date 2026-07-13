# US-001 macOS Screenshot To Draft

## Status

implemented

## Lane

normal

## Product Contract

Given a PNG, JPEG, or HEIC event screenshot selected on macOS, SnapCal validates
and reads the image locally, runs Apple Vision OCR, derives an evidence-bearing
event draft, and opens an editable review without writing to a calendar or
persisting the raw screenshot.

## Relevant Product Docs

- `docs/product/extraction.md`
- `docs/product/event-draft.md`
- `docs/product/review-calendar.md`
- `docs/product/privacy-quality.md`
- `docs/ARCHITECTURE.md`
- `docs/decisions/0008-snapcal-contract-and-first-slice.md`
- `docs/decisions/0009-human-review-evidence-and-retention.md`

## Acceptance Criteria

- The repository contains an openable macOS Xcode project with a SnapCal app
  and test target.
- The app accepts one PNG, JPEG, or HEIC through a native file importer.
- Unsupported, corrupt, empty, or oversized input fails before OCR and shows a
  concise recoverable error.
- Apple Vision OCR is configured for Vietnamese and English when supported.
- Recognized text is converted into a typed draft with editable title, start,
  location, description, evidence, confidence, and ambiguity warnings.
- Vietnamese `20h ngày 15/8` and an English month/date/time fixture produce
  deterministic draft dates in tests.
- Text without event-like date/time evidence returns `No event detected` rather
  than an invented date.
- No OAuth, cloud provider, persistence, or calendar write exists in this story.
- The app builds, tests, and launches on the installed macOS/Xcode toolchain.

## Design Notes

- Commands: import screenshot and start over.
- Queries: none.
- API: none; local service protocols isolate validation, OCR, and extraction.
- Tables: none; draft and source image remain in memory only.
- Domain rules: source evidence survives normalization and user edits; missing
  fields become ambiguities.
- UI surfaces: import, processing, error, and editable review states in one
  window.
- Deployment target: macOS 14.0 to use Swift Observation with Xcode 16.4.

## Validation

| Layer | Expected proof |
| --- | --- |
| Unit | image validation and Vietnamese/English/no-event extraction fixtures |
| Integration | root model moves valid imported OCR into review and failures into recoverable error |
| E2E | no automated external flow; file picker remains a platform boundary |
| Platform | `xcodebuild` app build/test and macOS launch smoke |
| Release | not in scope |

Verify command:

```bash
xcodebuild -project SnapCal.xcodeproj -scheme SnapCal \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test
```

## Harness Delta

US-001 becomes the first application behavior row. Update architecture and
README from “no app exists” to the exact implemented local prototype state.

## Evidence

- `xcodebuild -project SnapCal.xcodeproj -scheme SnapCal -destination
  'platform=macOS' -derivedDataPath .build/DerivedData
  CODE_SIGNING_ALLOWED=NO test` passes all 9 tests.
- A fresh Debug app build launches as `SnapCal`, creates a 920 x 680 macOS
  window, and exposes the selected-file entitlement without cloud/network
  entitlements.
- The app target contains no OAuth, network, persistence, or calendar adapter;
  the review action is visibly disabled and names calendar connection as the
  next story.
