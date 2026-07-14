# US-005 macOS Notch Drop Zone

## Status

in_progress

## Lane

normal

## Product Contract

Provide a persistent top-center macOS drop surface that visually attaches to
the display notch, expands on pointer hover or drag targeting, accepts a single
PNG, JPEG, or HEIC screenshot, and feeds the selected file into SnapCal's
existing extraction and mandatory-review flow.

## Relevant Product Docs

- `docs/product/platform-roadmap.md`
- `docs/product/extraction.md`
- `docs/product/review-calendar.md`

## Acceptance Criteria

- A compact, borderless top-center panel is visible across macOS spaces and
  expands when the pointer or a file drag enters it.
- Dropping a supported image starts the existing `SnapCalModel` import flow and
  brings the main review window forward.
- When multiple supported images are dropped, SnapCal processes only the first
  and visibly reports that the remaining images were ignored.
- Unsupported or empty drops do not call extraction and surface a recoverable
  import error.
- The drop surface follows the currently selected Local Only or Accuracy Mode.
- No drop directly creates a Calendar event; review and explicit confirmation
  remain mandatory.
- This slice does not add clipboard intake, recent-draft persistence,
  `MenuBarExtra`, or an iOS Dynamic Island surface.

## Design Notes

- Use an AppKit `NSPanel` for non-activating, all-spaces window behavior.
- Host a small SwiftUI view for hover, drag-target, accessibility, and visual
  state.
- Keep `SnapCalModel` as the sole extraction and Calendar state owner; the panel
  forwards only validated file-selection intent.
- Anchor panel resizing to the top-center of `NSScreen.frame` and account for
  the screen's safe-area top inset.

## Validation

| Layer | Expected proof |
| --- | --- |
| Unit | Deterministic panel geometry and first-supported-image selection |
| Integration | Dropped URL is forwarded to the existing import state machine |
| E2E | User drag from Finder into the live top-center surface |
| Platform | macOS build/tests plus visible compact, hover, target, and drop states |
| Release | Not required for this local vertical slice |

## Harness Delta

No Harness behavior change is expected.

## Evidence

- The macOS target builds and all 88 XCTest cases pass.
- `NotchDropZoneTests` proves compact/expanded top anchoring, safe-area sizing,
  containment of the compact hover region during expansion, edge-jitter
  tolerance, first-supported-image selection, multi-item reporting, and
  unsupported drops.
- `SnapCalModelTests.testNotchDropImporterFeedsExistingReviewFlow` proves the
  selected drop enters the existing review state without Calendar creation.
- `SnapCalUITests.testNotchHoverExpandsAndKeepsAStableFrame` moves the native
  pointer onto `notchDropZone`, waits for expansion, and proves its frame stays
  fixed across repeated samples.
- Finder drop remains user-driven E2E proof.
