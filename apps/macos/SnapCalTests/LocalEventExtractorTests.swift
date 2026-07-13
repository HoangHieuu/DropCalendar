import Foundation
import XCTest
@testable import SnapCal

final class LocalEventExtractorTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")!
        return calendar
    }

    func testExtractsVietnameseDateTimeAndPreservesEvidence() throws {
        let extractor = LocalEventExtractor(calendar: calendar)
        let draft = try extractor.extract(
            lines: [
                RecognizedTextLine(text: "Workshop: AI Agent for Students", confidence: 0.96),
                RecognizedTextLine(text: "20h ngày 15/8/2026", confidence: 0.94),
                RecognizedTextLine(text: "Đại học Bách Khoa TP.HCM", confidence: 0.91)
            ],
            capturedAt: makeDate(year: 2026, month: 7, day: 13, hour: 12),
            sourceFileName: "workshop.png"
        )

        XCTAssertEqual(draft.title.value, "Workshop: AI Agent for Students")
        XCTAssertEqual(draft.title.evidenceText, "Workshop: AI Agent for Students")
        XCTAssertEqual(draft.start.evidenceText, "20h ngày 15/8/2026")
        XCTAssertEqual(draft.location.value, "Đại học Bách Khoa TP.HCM")
        XCTAssertEqual(draft.detectedLanguage, .vietnamese)

        let start = try XCTUnwrap(draft.start.value)
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: start)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 8)
        XCTAssertEqual(components.day, 15)
        XCTAssertEqual(components.hour, 20)
        XCTAssertEqual(components.minute, 0)
    }

    func testExtractsEnglishMonthDateAndPMTime() throws {
        let extractor = LocalEventExtractor(calendar: calendar)
        let draft = try extractor.extract(
            lines: [
                RecognizedTextLine(text: "AI Founder Meetup", confidence: 0.97),
                RecognizedTextLine(text: "Friday, August 16, 2026 at 7:00 PM", confidence: 0.95),
                RecognizedTextLine(text: "Dreamplex, District 1, Ho Chi Minh City", confidence: 0.92)
            ],
            capturedAt: makeDate(year: 2026, month: 7, day: 13, hour: 12),
            sourceFileName: "meetup.jpg"
        )

        let start = try XCTUnwrap(draft.start.value)
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: start)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 8)
        XCTAssertEqual(components.day, 16)
        XCTAssertEqual(components.hour, 19)
        XCTAssertEqual(components.minute, 0)
        XCTAssertEqual(draft.detectedLanguage, .english)
    }

    func testReturnsNoEventInsteadOfInventingDate() {
        let extractor = LocalEventExtractor(calendar: calendar)

        XCTAssertThrowsError(try extractor.extract(
            lines: [RecognizedTextLine(text: "A nice photo from our club", confidence: 0.99)],
            capturedAt: makeDate(year: 2026, month: 7, day: 13, hour: 12),
            sourceFileName: "photo.png"
        )) { error in
            XCTAssertEqual(error as? DraftExtractionError, .noEventDetected)
        }
    }

    func testMissingLocationCreatesVisibleAmbiguity() throws {
        let extractor = LocalEventExtractor(calendar: calendar)
        let draft = try extractor.extract(
            lines: [
                RecognizedTextLine(text: "Community Workshop", confidence: 0.95),
                RecognizedTextLine(text: "15/8/2026 19:30", confidence: 0.93)
            ],
            capturedAt: makeDate(year: 2026, month: 7, day: 13, hour: 12),
            sourceFileName: "community.png"
        )

        XCTAssertTrue(draft.ambiguities.contains { $0.field == .location })
        XCTAssertNil(draft.location.value)
    }

    private func makeDate(year: Int, month: Int, day: Int, hour: Int) -> Date {
        calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour
        ))!
    }
}
