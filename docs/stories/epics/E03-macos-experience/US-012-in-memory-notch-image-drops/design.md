# Design

## Domain Model

`NotchDropSelection` contains either a supported local file URL or a
`ClipboardImage`-shaped in-memory image value plus the number of ignored drag
items. The value carries bytes, a format-derived filename, and a capture time;
it carries no provider object beyond the loading boundary.

## Application Flow

1. SwiftUI exposes the drag's `NSItemProvider` values to the notch controller.
2. The loader considers providers in order and uses the first supported image.
3. A supported local file URL keeps the existing security-scoped file path.
4. PNG, JPEG, and HEIC data are loaded directly into memory. TIFF is converted
   to PNG in memory. A temporary image representation is read while its URL is
   valid, then released.
5. `SnapCalModel` validates the file or in-memory image with the existing image
   validator and continues through the existing extraction pipeline.
6. The main window opens in mandatory review. Calendar creation remains a
   separate explicit user action.

## Interface Contract

The UI callback changes from `[URL]` to `[NSItemProvider]`. The loader returns a
typed selection or `empty`/`unsupported` error. The model adds an in-memory
image import entry point shared by notch and clipboard imports.

## Data Model

No database or migration changes. Raw bytes live only in the import value and
the existing validated-image lifecycle. Default screenshot retention remains
off; optional encrypted history remains governed by decision 0018.

## UI / Platform Impact

The notch advertises file-URL and supported image uniform types. Hover and
panel sizing remain unchanged. Existing busy-state handling, first-image
selection, ignored-item messaging, and accessibility copy remain in place.

## Observability

No image bytes, filenames, OCR transcript, or event content are logged. User
errors remain generic and recoverable.

## Alternatives Considered

1. Copy every drop into a SnapCal temporary file. Rejected because validation
   already accepts in-memory bytes and an app-owned copy adds retention risk.
2. Continue accepting only URLs. Rejected because floating screenshots are a
   first-class macOS input and do not reliably expose a stable named URL.
3. Accept generic remote URLs. Rejected because it adds network, consent, and
   download-validation behavior outside this story.

