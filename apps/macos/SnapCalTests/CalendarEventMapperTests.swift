import Foundation
import XCTest
@testable import SnapCal

final class CalendarEventMapperTests: XCTestCase {
    private let timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")!

    func testMapsTimedEventWithoutChangingReviewedValues() throws {
        let start = Date(timeIntervalSince1970: 1_787_415_400)
        let end = start.addingTimeInterval(5_400)
        let request = try CalendarEventMapper.request(
            from: makeDraft(start: start, end: end),
            timeZone: timeZone
        )

        XCTAssertEqual(request.summary, "AI Workshop")
        XCTAssertEqual(request.location, "District 1")
        guard case .timed(let mappedStart, let mappedEnd, let mappedTimeZone) = request.timing else {
            return XCTFail("Expected timed event")
        }
        XCTAssertEqual(mappedStart, start)
        XCTAssertEqual(mappedEnd, end)
        XCTAssertEqual(mappedTimeZone, timeZone)
    }

    func testAllDayEndIsExclusive() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let start = calendar.date(from: DateComponents(year: 2026, month: 8, day: 15))!
        let draft = makeDraft(start: start, end: start, isAllDay: true)

        let request = try CalendarEventMapper.request(
            from: draft,
            timeZone: timeZone,
            calendar: calendar
        )

        guard case .allDay(let mappedStart, let endExclusive, _) = request.timing else {
            return XCTFail("Expected all-day event")
        }
        XCTAssertEqual(mappedStart, start)
        XCTAssertEqual(endExclusive, calendar.date(byAdding: .day, value: 1, to: start))
    }

    func testMultiDayAllDayEndIncludesReviewedEndDate() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let start = calendar.date(from: DateComponents(year: 2026, month: 7, day: 8))!
        let inclusiveEnd = calendar.date(from: DateComponents(year: 2026, month: 7, day: 12))!

        let request = try CalendarEventMapper.request(
            from: makeDraft(start: start, end: inclusiveEnd, isAllDay: true),
            timeZone: timeZone,
            calendar: calendar
        )

        guard case .allDay(_, let endExclusive, _) = request.timing else {
            return XCTFail("Expected all-day event")
        }
        XCTAssertEqual(
            endExclusive,
            calendar.date(from: DateComponents(year: 2026, month: 7, day: 13))
        )
    }

    func testRejectsMissingTitleAndInvalidEnd() {
        var missingTitle = makeDraft(start: Date(), end: Date().addingTimeInterval(3_600))
        missingTitle.title = ExtractedField(value: nil, evidenceText: nil, confidence: 0)
        XCTAssertThrowsError(try CalendarEventMapper.request(from: missingTitle))

        let start = Date()
        XCTAssertThrowsError(try CalendarEventMapper.request(from: makeDraft(start: start, end: start)))
    }

    private func makeDraft(start: Date, end: Date, isAllDay: Bool = false) -> EventDraft {
        EventDraft(
            capturedAt: start,
            sourceFileName: "event.png",
            detectedLanguage: .english,
            rawOCRText: "AI Workshop",
            title: ExtractedField(value: " AI Workshop ", evidenceText: "AI Workshop", confidence: 0.9),
            start: ExtractedField(value: start, evidenceText: "Aug 15", confidence: 0.9),
            end: ExtractedField(value: end, evidenceText: "Default duration", confidence: 0.5, isInferred: true),
            location: ExtractedField(value: " District 1 ", evidenceText: "District 1", confidence: 0.8),
            description: ExtractedField(value: "", evidenceText: nil, confidence: 0),
            isAllDay: isAllDay,
            ambiguities: []
        )
    }
}
