import AppKit
import XCTest
import UniformTypeIdentifiers
@testable import SnapCal

final class NotchDropZoneTests: XCTestCase {
    func testPanelStaysBelowMenuBarStatusItems() {
        XCTAssertEqual(NotchPanelLayout.windowLevel, .mainMenu)
        XCTAssertLessThan(
            NotchPanelLayout.windowLevel.rawValue,
            NSWindow.Level.statusBar.rawValue
        )
        XCTAssertGreaterThan(
            NotchPanelLayout.windowLevel.rawValue,
            NSWindow.Level.normal.rawValue
        )
    }

    func testCollapsedPanelAnchorsToTopCenterAndUsesNotchInset() {
        let frame = NotchPanelLayout.frame(
            in: CGRect(x: 100, y: 50, width: 1_440, height: 900),
            topInset: 38,
            isExpanded: false
        )

        XCTAssertEqual(frame.width, 184)
        XCTAssertEqual(frame.height, 38)
        XCTAssertEqual(frame.midX, 820)
        XCTAssertEqual(frame.maxY, 950)
    }

    func testExpandedPanelKeepsItsTopEdgeAnchored() {
        let frame = NotchPanelLayout.frame(
            in: CGRect(x: -1_920, y: 0, width: 1_920, height: 1_080),
            topInset: 0,
            isExpanded: true
        )

        XCTAssertEqual(frame.size, NotchPanelLayout.expandedSize)
        XCTAssertEqual(frame.midX, -960)
        XCTAssertEqual(frame.maxY, 1_080)
    }

    func testExpandedPanelContainsTheEntireCollapsedHoverRegion() {
        let screenFrame = CGRect(x: 100, y: 50, width: 1_440, height: 900)
        let collapsedFrame = NotchPanelLayout.frame(
            in: screenFrame,
            topInset: 38,
            isExpanded: false
        )
        let expandedFrame = NotchPanelLayout.frame(
            in: screenFrame,
            topInset: 38,
            isExpanded: true
        )

        XCTAssertTrue(expandedFrame.contains(collapsedFrame))
    }

    func testHoverExitPolicyRetainsPointerAcrossSmallTrackingAreaJitter() {
        let panelFrame = CGRect(x: 100, y: 700, width: 372, height: 148)

        XCTAssertTrue(NotchHoverExitPolicy.containsPointer(
            CGPoint(x: panelFrame.minX - 5, y: panelFrame.midY),
            in: panelFrame
        ))
        XCTAssertFalse(NotchHoverExitPolicy.containsPointer(
            CGPoint(x: panelFrame.minX - 7, y: panelFrame.midY),
            in: panelFrame
        ))
    }

    func testDropSelectionUsesFirstSupportedImageAndReportsIgnoredItems() throws {
        let selection = try NotchDropSelection.select(from: [
            URL(fileURLWithPath: "/tmp/readme.txt"),
            URL(fileURLWithPath: "/tmp/poster.HEIC"),
            URL(fileURLWithPath: "/tmp/second.png")
        ])

        XCTAssertEqual(selection.payload, .file(URL(fileURLWithPath: "/tmp/poster.HEIC")))
        XCTAssertEqual(selection.ignoredItemCount, 2)
    }

    func testDropSelectionRejectsEmptyAndUnsupportedDrops() {
        XCTAssertThrowsError(try NotchDropSelection.select(from: [])) { error in
            XCTAssertEqual(error as? NotchDropSelectionError, .empty)
        }
        XCTAssertThrowsError(try NotchDropSelection.select(from: [
            URL(string: "https://example.com/poster.png")!,
            URL(fileURLWithPath: "/tmp/event.pdf")
        ])) { error in
            XCTAssertEqual(error as? NotchDropSelectionError, .unsupported)
        }
    }

    @MainActor
    func testProviderLoaderAcceptsImageDataAndReportsIgnoredItems() async throws {
        let capturedAt = Date(timeIntervalSince1970: 1_783_930_400)
        let pngData = Data([0x89, 0x50, 0x4E, 0x47])
        let unsupported = NSItemProvider(
            item: "not an image" as NSString,
            typeIdentifier: UTType.plainText.identifier
        )
        let image = NSItemProvider()
        image.registerDataRepresentation(
            forTypeIdentifier: UTType.png.identifier,
            visibility: .all
        ) { completion in
            completion(pngData, nil)
            return nil
        }

        let selection = try await NotchDropProviderLoader(now: { capturedAt }).select(
            from: [unsupported, image]
        )

        XCTAssertEqual(selection.payload, .image(ClipboardImage(
            data: pngData,
            fileName: "Dropped Screenshot.png",
            capturedAt: capturedAt
        )))
        XCTAssertEqual(selection.ignoredItemCount, 1)
    }

    @MainActor
    func testProviderLoaderRejectsUnsupportedRepresentations() async {
        let provider = NSItemProvider(
            item: "not an image" as NSString,
            typeIdentifier: UTType.plainText.identifier
        )

        do {
            _ = try await NotchDropProviderLoader().select(from: [provider])
            XCTFail("Expected unsupported drop")
        } catch {
            XCTAssertEqual(error as? NotchDropSelectionError, .unsupported)
        }
    }

    @MainActor
    func testProviderLoaderReadsTemporaryImageBeforeItsURLExpires() async throws {
        let sourceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")
        try makeBitmapData(format: .png).write(to: sourceURL)
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let provider = NSItemProvider()
        provider.registerFileRepresentation(
            forTypeIdentifier: UTType.image.identifier,
            fileOptions: [],
            visibility: .all
        ) { completion in
            completion(sourceURL, true, nil)
            return nil
        }

        let selection = try await NotchDropProviderLoader().select(from: [provider])
        guard case .image(let image) = selection.payload else {
            return XCTFail("Expected an in-memory image")
        }

        try FileManager.default.removeItem(at: sourceURL)
        let validated = try ImageValidator().validate(image)
        XCTAssertEqual(image.fileName, "Dropped Screenshot.png")
        XCTAssertEqual(validated.cgImage.width, 2)
        XCTAssertEqual(validated.cgImage.height, 2)
    }

    @MainActor
    func testProviderLoaderCopiesFileURLBytesBeforeTheSourceExpires() async throws {
        let sourceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")
        try makeBitmapData(format: .png).write(to: sourceURL)
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let provider = NSItemProvider()
        provider.registerItem(
            forTypeIdentifier: UTType.fileURL.identifier,
            loadHandler: { completion, _, _ in
                completion?(sourceURL as NSURL, nil)
            }
        )

        let selection = try await NotchDropProviderLoader().select(from: [provider])
        guard case .image(let image) = selection.payload else {
            return XCTFail("Expected an in-memory image")
        }

        try FileManager.default.removeItem(at: sourceURL)
        let validated = try ImageValidator().validate(image)
        XCTAssertEqual(validated.cgImage.width, 2)
        XCTAssertEqual(validated.cgImage.height, 2)
    }

    @MainActor
    func testProviderLoaderConvertsTIFFDataToPNG() async throws {
        let tiffData = try makeBitmapData(format: .tiff)
        let provider = NSItemProvider()
        provider.registerDataRepresentation(
            forTypeIdentifier: UTType.tiff.identifier,
            visibility: .all
        ) { completion in
            completion(tiffData, nil)
            return nil
        }

        let selection = try await NotchDropProviderLoader().select(from: [provider])
        guard case .image(let image) = selection.payload else {
            return XCTFail("Expected an in-memory image")
        }

        let validated = try ImageValidator().validate(image)
        XCTAssertEqual(image.fileName, "Dropped Screenshot.png")
        XCTAssertEqual(validated.cgImage.width, 2)
        XCTAssertEqual(validated.cgImage.height, 2)
    }

    private func makeBitmapData(format: NSBitmapImageRep.FileType) throws -> Data {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 2,
            pixelsHigh: 2,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        switch format {
        case .tiff:
            return try XCTUnwrap(bitmap.tiffRepresentation)
        default:
            return try XCTUnwrap(bitmap.representation(using: format, properties: [:]))
        }
    }
}
