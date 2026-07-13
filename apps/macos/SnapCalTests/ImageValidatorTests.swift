import AppKit
import XCTest
@testable import SnapCal

final class ImageValidatorTests: XCTestCase {
    func testRejectsUnsupportedExtensionBeforeReadingFile() {
        let url = URL(fileURLWithPath: "/tmp/event-poster.txt")

        XCTAssertThrowsError(try ImageValidator().validate(url)) { error in
            XCTAssertEqual(error as? ImageValidationError, .unsupportedFormat)
        }
    }

    func testAcceptsDecodablePNG() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")
        defer { try? FileManager.default.removeItem(at: url) }

        try makePNGData().write(to: url)
        let result = try ImageValidator().validate(url)

        XCTAssertEqual(result.fileName, url.lastPathComponent)
        XCTAssertEqual(result.cgImage.width, 2)
        XCTAssertEqual(result.cgImage.height, 2)
    }

    func testRejectsCorruptImageWithAllowedExtension() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("jpg")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("not an image".utf8).write(to: url)

        XCTAssertThrowsError(try ImageValidator().validate(url)) { error in
            XCTAssertEqual(error as? ImageValidationError, .corruptImage)
        }
    }

    private func makePNGData() throws -> Data {
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
        return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    }
}
