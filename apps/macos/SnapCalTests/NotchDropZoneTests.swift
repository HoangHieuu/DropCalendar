import XCTest
@testable import SnapCal

final class NotchDropZoneTests: XCTestCase {
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

    func testDropSelectionUsesFirstSupportedImageAndReportsIgnoredItems() throws {
        let selection = try NotchDropSelection.select(from: [
            URL(fileURLWithPath: "/tmp/readme.txt"),
            URL(fileURLWithPath: "/tmp/poster.HEIC"),
            URL(fileURLWithPath: "/tmp/second.png")
        ])

        XCTAssertEqual(selection.url.lastPathComponent, "poster.HEIC")
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
}
