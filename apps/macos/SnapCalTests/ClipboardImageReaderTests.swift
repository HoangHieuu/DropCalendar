import AppKit
import XCTest
@testable import SnapCal

@MainActor
final class ClipboardImageReaderTests: XCTestCase {
    private var pasteboard: NSPasteboard!

    override func setUp() {
        super.setUp()
        pasteboard = NSPasteboard(
            name: NSPasteboard.Name("SnapCalTests.\(UUID().uuidString)")
        )
        pasteboard.clearContents()
    }

    override func tearDown() {
        pasteboard.clearContents()
        pasteboard = nil
        super.tearDown()
    }

    func testReadsPNGBytesWithoutCreatingAFile() throws {
        let capturedAt = Date(timeIntervalSince1970: 1_784_000_000)
        let pngData = try makeBitmap().representation(using: .png, properties: [:])
        XCTAssertNotNil(pngData)
        pasteboard.setData(try XCTUnwrap(pngData), forType: .png)

        let result = try SystemClipboardImageReader(
            pasteboard: pasteboard,
            now: { capturedAt }
        ).readImage()

        XCTAssertEqual(result.data, pngData)
        XCTAssertEqual(result.fileName, "Clipboard Screenshot.png")
        XCTAssertEqual(result.capturedAt, capturedAt)
    }

    func testPrefersNativePNGOverTIFFFallback() throws {
        let bitmap = try makeBitmap()
        let pngData = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let tiffData = try XCTUnwrap(bitmap.tiffRepresentation)
        pasteboard.setData(tiffData, forType: .tiff)
        pasteboard.setData(pngData, forType: .png)

        let result = try SystemClipboardImageReader(pasteboard: pasteboard).readImage()

        XCTAssertEqual(result.fileName, "Clipboard Screenshot.png")
        XCTAssertEqual(result.data, pngData)
    }

    func testConvertsTIFFClipboardRepresentationToBoundedPNGInput() throws {
        let tiffData = try XCTUnwrap(try makeBitmap().tiffRepresentation)
        pasteboard.setData(tiffData, forType: .tiff)

        let clipboardImage = try SystemClipboardImageReader(pasteboard: pasteboard).readImage()
        let validated = try ImageValidator().validate(clipboardImage)

        XCTAssertEqual(clipboardImage.fileName, "Clipboard Screenshot.png")
        XCTAssertEqual(validated.cgImage.width, 2)
        XCTAssertEqual(validated.cgImage.height, 2)
    }

    func testRejectsClipboardWithoutSupportedImageRepresentation() {
        pasteboard.setString("Event details only", forType: .string)

        XCTAssertThrowsError(
            try SystemClipboardImageReader(pasteboard: pasteboard).readImage()
        ) { error in
            XCTAssertEqual(error as? ClipboardImageReadingError, .noSupportedImage)
        }
    }

    private func makeBitmap() throws -> NSBitmapImageRep {
        try XCTUnwrap(NSBitmapImageRep(
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
    }
}
