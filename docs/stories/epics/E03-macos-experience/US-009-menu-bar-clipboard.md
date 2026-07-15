# US-009 macOS Menu Bar And Clipboard Intake

## Status

implemented; platform smoke revalidation pending

## Lane

normal

## Product Contract

Provide a persistent `MenuBarExtra` that shares the existing `SnapCalModel`,
opens the main window, exposes the current extraction mode, and imports a copied
PNG/JPEG/HEIC image directly from the macOS pasteboard into the same extraction
and mandatory-review flow. Clipboard bytes remain memory-only.

## Relevant Product Docs

- `docs/product/platform-roadmap.md`
- `docs/product/extraction.md`
- `docs/product/privacy-quality.md`
- `docs/product/review-calendar.md`

## Acceptance Criteria

- A SnapCal menu-bar item is available while the app runs.
- The menu-bar surface can open or reveal the main SnapCal window.
- A copied supported image starts extraction and opens review.
- Missing, empty, oversized, unsupported, or corrupt clipboard content produces
  a recoverable error without a cloud or Calendar call.
- Clipboard import uses in-memory bytes and creates no temporary screenshot file.
- The menu-bar mode picker updates the same Local Only/Accuracy Mode state used
  by manual import and the notch drop zone.
- No clipboard action creates a Calendar event without review and explicit
  confirmation.

## Design Notes

- Commands: `importClipboardImage()` on the shared application model.
- Queries: pasteboard reader returns a bounded `ClipboardImage` value.
- API: none.
- Tables: none.
- Domain rules: the existing image validator, OCR, extraction, review, and
  Calendar confirmation boundaries remain authoritative.
- UI surfaces: `MenuBarExtra` plus a Paste Screenshot button on the import view.

## Validation

| Layer | Expected proof |
| --- | --- |
| Unit | Pasteboard type selection and in-memory image validation |
| Integration | Clipboard image enters the shared review flow; missing data is recoverable; zero Calendar calls |
| E2E | Copy an image in Finder/Preview, choose Paste Screenshot, inspect review |
| Platform | macOS build and visible menu-bar item |
| Release | Not required for the local vertical slice |

## Harness Delta

No Harness behavior change is expected.

## Evidence

- `SystemClipboardImageReader` accepts PNG/JPEG/HEIC plus TIFF conversion in
  memory and never creates a temporary file.
- `SnapCalMenuBarView` and `MenuBarExtra` share the root `SnapCalModel`; the
  main import view exposes the same Paste Screenshot command.
- `ClipboardImageReaderTests`, `ImageValidatorTests`, and `SnapCalModelTests`
  prove type choice, validation limits, recoverable missing input, shared
  review flow, and zero Calendar writes.
- `SnapCalUITests` runs with a distinct app bundle, isolated SQLite database,
  disabled cloud/Calendar dependencies, and restored pasteboard contents.
- The 2026-07-14 full macOS suite passed all 86 tests. The separate two-case UI
  smoke suite passed: it clicked the app-owned status item and found the menu
  clipboard action, then imported a PNG through production clipboard/Vision/
  Local Only code, reached Review, relaunched, and reopened the persisted
  draft. No Calendar action was invoked.
- Reproduce with `scripts/run-ui-smoke.sh`.
- On 2026-07-15, a later three-case smoke found the status item present but not
  hittable while the notch panel was ordered at the same `.statusBar` window
  level. The panel now uses `.mainMenu` so app and system status items remain
  above it, and the custom menu-bar label exposes `SnapCal` instead of the SF
  Symbol description. The macOS unit suite passes the level invariant; direct
  app inspection sees the labeled item. Final automated click revalidation is
  pending because the local Xcode runner currently times out enabling UI
  automation before executing any test method.
