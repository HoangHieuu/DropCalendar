# Validation

## Proof Strategy

Prove that every phase owns the full window, the ready screen reaches the
trailing edge at full-screen sizes, wide and compact review compositions retain
the same controls and reading order, the notch geometry remains stable, and no
behavioral safety boundary changes.

## Test Plan

| Layer | Cases |
| --- | --- |
| Unit | Existing notch geometry, drop-selection, and model safety tests |
| Integration | Existing import-to-review and zero-Calendar-write model tests |
| E2E | Clipboard import reaches redesigned review; saved draft reopens |
| Platform | Build and launch on macOS; inspect default, compact, and full-screen ready/review states; hover notch |
| Performance | Decorative canvas remains static/lightweight and does not block interaction |
| Logs/Audit | No private screenshot/OCR/event content added to logs or Harness traces |

## Fixtures

- Existing isolated macOS UI-test storage.
- Existing generated `en-051.png` clipboard fixture.
- Empty recent-history state and persisted draft state.

## Commands

```text
xcodebuild -project SnapCal.xcodeproj -scheme SnapCal -destination 'platform=macOS' -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO test
scripts/run-ui-smoke.sh
```

## Acceptance Evidence

- `xcodebuild -project SnapCal.xcodeproj -scheme SnapCal -destination
  'platform=macOS' -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO
  build` — passed on 2026-07-17.
- Focused `NotchDropZoneTests` and `SnapCalModelTests` — 39 tests passed, zero
  failures on 2026-07-17.
- `SnapCalUITests.testFullscreenReadyLayoutClaimsTrailingEdge` — passed on
  2026-07-17; the adaptive history rail reached the window's trailing edge.
- `SnapCalUITests.testNotchHoverExpandsAndKeepsAStableFrame` — passed on
  2026-07-17; the themed notch panel retained its tested geometry while
  expanding.
- `SnapCalUITests.testImportShowsExactlyLocalSemanticAndAccuracyModes` —
  passed on 2026-07-17; the two visible modes and truthful local fallback
  disclosure remain exposed.
- `SnapCalUITests.testClipboardImportPersistsDraftAcrossRelaunch` — passed on
  2026-07-17; the redesigned import path still reaches editable review and
  reopens the locally persisted draft.
- Manual visual inspection confirmed the default and full-screen ready shells
  have intentional full-bleed composition with no unowned trailing strip.
- `scripts/run-ui-smoke.sh` — all 5 macOS UI smoke tests passed on 2026-07-17,
  including menu-bar clipboard entry, notch hover stability, import-mode
  contract, clipboard-to-review persistence, and full-screen trailing-edge
  ownership. No Calendar write was made.
