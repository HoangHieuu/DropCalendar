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

    func testExtractsVietnameseWordFormDateAndAMTime() throws {
        let extractor = LocalEventExtractor(calendar: calendar)
        let evidence = "02:00 AM (2 giờ sáng) thứ Bảy, ngày 18 tháng 7 tại Việt Nam."
        let draft = try extractor.extract(
            lines: [
                RecognizedTextLine(text: "Lịch phát sóng", confidence: 0.97),
                RecognizedTextLine(text: evidence, confidence: 0.95),
            ],
            capturedAt: makeDate(year: 2026, month: 7, day: 16, hour: 21),
            sourceFileName: "vietnamese-word-date.png"
        )

        let start = try XCTUnwrap(draft.start.value)
        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: start
        )
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 7)
        XCTAssertEqual(components.day, 18)
        XCTAssertEqual(components.hour, 2)
        XCTAssertEqual(components.minute, 0)
        XCTAssertEqual(draft.start.evidenceText, evidence)
        XCTAssertTrue(draft.start.isInferred)
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

    func testLayoutAwarePosterBecomesAllDayDateRange() throws {
        let extractor = LocalEventExtractor(calendar: calendar)
        let draft = try extractor.extract(
            lines: [
                RecognizedTextLine(text: "GenAI Fund", confidence: 0.99, region: region(y: 0.89, height: 0.04)),
                RecognizedTextLine(text: "AGENTIC AI", confidence: 0.98, region: region(y: 0.70, height: 0.09)),
                RecognizedTextLine(text: "BUILD WEEK", confidence: 0.98, region: region(y: 0.59, height: 0.09)),
                RecognizedTextLine(text: "July 8", confidence: 0.96, region: region(y: 0.43, height: 0.035)),
                RecognizedTextLine(text: "July 12,", confidence: 0.96, region: region(y: 0.43, height: 0.035)),
                RecognizedTextLine(text: "2026", confidence: 0.97, region: region(y: 0.39, height: 0.03)),
                RecognizedTextLine(text: "5 Days (Workshops + Hackathon)", confidence: 0.94, region: region(y: 0.34, height: 0.03)),
                RecognizedTextLine(text: "Ho Chi Minh, Vietnam", confidence: 0.95, region: region(y: 0.29, height: 0.03))
            ],
            capturedAt: makeDate(year: 2026, month: 7, day: 13, hour: 20),
            sourceFileName: "1.jpg"
        )

        XCTAssertEqual(draft.title.value, "AGENTIC AI BUILD WEEK")
        XCTAssertTrue(draft.isAllDay)
        XCTAssertEqual(
            calendar.dateComponents([.year, .month, .day], from: try XCTUnwrap(draft.start.value)),
            DateComponents(year: 2026, month: 7, day: 8)
        )
        XCTAssertEqual(
            calendar.dateComponents([.year, .month, .day], from: try XCTUnwrap(draft.end.value)),
            DateComponents(year: 2026, month: 7, day: 12)
        )
        XCTAssertEqual(draft.location.value, "Ho Chi Minh, Vietnam")
        XCTAssertTrue(draft.ambiguities.contains {
            $0.field == .dateTime && $0.message.contains("all-day")
        })
    }

    func testResolvesTomorrowFromCaptureTimeAndMarksDateInferred() throws {
        let extractor = LocalEventExtractor(calendar: calendar)
        let draft = try extractor.extract(
            lines: [
                RecognizedTextLine(text: "AI Community Night", confidence: 0.97),
                RecognizedTextLine(text: "Tomorrow at 8 PM", confidence: 0.95),
                RecognizedTextLine(text: "Dreamplex, District 1", confidence: 0.93)
            ],
            capturedAt: makeDate(year: 2026, month: 7, day: 13, hour: 12),
            sourceFileName: "tomorrow.png"
        )

        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: try XCTUnwrap(draft.start.value)
        )
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 7)
        XCTAssertEqual(components.day, 14)
        XCTAssertEqual(components.hour, 20)
        XCTAssertTrue(draft.start.isInferred)
    }

    func testResolvesVietnameseWeekdayOnlyInTimeContext() throws {
        let extractor = LocalEventExtractor(calendar: calendar)
        let draft = try extractor.extract(
            lines: [
                RecognizedTextLine(text: "Sinh hoạt cộng đồng", confidence: 0.96),
                RecognizedTextLine(text: "T7 lúc 20h", confidence: 0.94),
                RecognizedTextLine(text: "Đại học Bách Khoa TP.HCM", confidence: 0.92)
            ],
            capturedAt: makeDate(year: 2026, month: 7, day: 13, hour: 12),
            sourceFileName: "saturday.png"
        )

        let components = calendar.dateComponents(
            [.year, .month, .day, .hour],
            from: try XCTUnwrap(draft.start.value)
        )
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 7)
        XCTAssertEqual(components.day, 18)
        XCTAssertEqual(components.hour, 20)
    }

    func testResolvesVietnameseWordWeekdayOnlyInTimeContext() throws {
        let extractor = LocalEventExtractor(calendar: calendar)
        let draft = try extractor.extract(
            lines: [
                RecognizedTextLine(text: "Sinh hoạt cộng đồng", confidence: 0.96),
                RecognizedTextLine(text: "thứ Bảy lúc 02:00 AM", confidence: 0.94),
            ],
            capturedAt: makeDate(year: 2026, month: 7, day: 16, hour: 21),
            sourceFileName: "saturday-word.png"
        )

        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: try XCTUnwrap(draft.start.value)
        )
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 7)
        XCTAssertEqual(components.day, 18)
        XCTAssertEqual(components.hour, 2)
        XCTAssertEqual(components.minute, 0)
        XCTAssertTrue(draft.start.isInferred)
    }

    func testPrefersShowStartOverDoorsOpenTime() throws {
        let extractor = LocalEventExtractor(calendar: calendar)
        let draft = try extractor.extract(
            lines: [
                RecognizedTextLine(text: "Summer Performance", confidence: 0.97),
                RecognizedTextLine(text: "August 16, 2026", confidence: 0.95),
                RecognizedTextLine(text: "Doors open at 6 PM, show starts at 7 PM", confidence: 0.94),
                RecognizedTextLine(text: "University Auditorium", confidence: 0.92)
            ],
            capturedAt: makeDate(year: 2026, month: 7, day: 13, hour: 12),
            sourceFileName: "performance.png"
        )

        XCTAssertEqual(
            calendar.component(.hour, from: try XCTUnwrap(draft.start.value)),
            19
        )
    }

    func testPrefersEventDateOverRegistrationDeadlineAndFlagsMultipleDates() throws {
        let extractor = LocalEventExtractor(calendar: calendar)
        let draft = try extractor.extract(
            lines: [
                RecognizedTextLine(text: "AI Builder Workshop", confidence: 0.97),
                RecognizedTextLine(text: "Registration deadline August 15, 2026", confidence: 0.95),
                RecognizedTextLine(text: "Event starts August 20, 2026 at 7 PM", confidence: 0.94),
                RecognizedTextLine(text: "Dreamplex, District 1", confidence: 0.92)
            ],
            capturedAt: makeDate(year: 2026, month: 7, day: 13, hour: 12),
            sourceFileName: "deadline.png"
        )

        let components = calendar.dateComponents(
            [.year, .month, .day, .hour],
            from: try XCTUnwrap(draft.start.value)
        )
        XCTAssertEqual(components.day, 20)
        XCTAssertEqual(components.hour, 19)
        XCTAssertTrue(draft.ambiguities.contains {
            $0.field == .dateTime && $0.message.contains("Multiple possible dates")
        })
    }

    func testWeekdayConflictLowersConfidenceAndAddsHighAmbiguity() throws {
        let extractor = LocalEventExtractor(calendar: calendar)
        let draft = try extractor.extract(
            lines: [
                RecognizedTextLine(text: "AI Founder Meetup", confidence: 0.97),
                RecognizedTextLine(text: "Monday, August 16, 2026 at 7 PM", confidence: 0.95),
                RecognizedTextLine(text: "Dreamplex, District 1", confidence: 0.92)
            ],
            capturedAt: makeDate(year: 2026, month: 7, day: 13, hour: 12),
            sourceFileName: "weekday-conflict.png"
        )

        XCTAssertLessThanOrEqual(draft.start.confidence, 0.49)
        XCTAssertTrue(draft.ambiguities.contains {
            $0.field == .dateTime && $0.severity == .high && $0.message.contains("weekday")
        })
    }

    func testCorrectsLetterOTimeOnlyAtHighConfidence() throws {
        let extractor = LocalEventExtractor(calendar: calendar)
        let highConfidence = try extractor.extract(
            lines: [
                RecognizedTextLine(text: "Đêm công nghệ", confidence: 0.97),
                RecognizedTextLine(text: "20:OO ngày 15/8/2026", confidence: 0.95),
                RecognizedTextLine(text: "Đại học Bách Khoa TP.HCM", confidence: 0.92)
            ],
            capturedAt: makeDate(year: 2026, month: 7, day: 13, hour: 12),
            sourceFileName: "high-confidence.png"
        )
        let lowConfidence = try extractor.extract(
            lines: [
                RecognizedTextLine(text: "Đêm công nghệ", confidence: 0.97),
                RecognizedTextLine(text: "20:OO ngày 15/8/2026", confidence: 0.70),
                RecognizedTextLine(text: "Đại học Bách Khoa TP.HCM", confidence: 0.92)
            ],
            capturedAt: makeDate(year: 2026, month: 7, day: 13, hour: 12),
            sourceFileName: "low-confidence.png"
        )

        XCTAssertEqual(
            calendar.component(.hour, from: try XCTUnwrap(highConfidence.start.value)),
            20
        )
        XCTAssertFalse(highConfidence.isAllDay)
        XCTAssertTrue(lowConfidence.isAllDay)
        XCTAssertTrue(lowConfidence.ambiguities.contains { $0.field == .dateTime })
    }

    func testSpecificLocationBeatsGenericSourceCategoryLabel() throws {
        let extractor = LocalEventExtractor(calendar: calendar)
        let draft = try extractor.extract(
            lines: [
                RecognizedTextLine(text: "UNIVERSITY", confidence: 0.99),
                RecognizedTextLine(text: "AI Community Meetup", confidence: 0.97),
                RecognizedTextLine(text: "August 16, 2026 at 7 PM", confidence: 0.95),
                RecognizedTextLine(text: "University Campus, Ho Chi Minh City", confidence: 0.92)
            ],
            capturedAt: makeDate(year: 2026, month: 7, day: 13, hour: 12),
            sourceFileName: "university.png"
        )

        XCTAssertEqual(draft.location.value, "University Campus, Ho Chi Minh City")
    }

    func testExtractsTwoVietnameseTrainingEventsWithoutInventingEveningTimes() throws {
        let extractor = LocalEventExtractor(calendar: calendar)
        let drafts = try extractor.extractEvents(
            lines: [
                RecognizedTextLine(text: "Thông báo về buổi training AI RACE 2026", confidence: 0.98),
                RecognizedTextLine(text: "1) Do btc vừa cập nhật lại đề thi cho bài 1, nên buổi training bài 1", confidence: 0.96),
                RecognizedTextLine(text: "sẽ dời qua tối chủ nhật ngày 19/07/2026", confidence: 0.96),
                RecognizedTextLine(text: "2) Buổi training cho bài 2 sẽ diễn ra vào tối thứ 5 ngày", confidence: 0.95),
                RecognizedTextLine(text: "16/07/2026.", confidence: 0.95),
                RecognizedTextLine(text: "Các bạn cập nhật lại lịch dùm ad nhé.", confidence: 0.94),
            ],
            capturedAt: makeDate(year: 2026, month: 7, day: 15, hour: 9),
            sourceFileName: "training.png"
        )

        XCTAssertEqual(drafts.count, 2)
        XCTAssertEqual(drafts[0].title.value, "buổi training bài 1")
        XCTAssertEqual(drafts[1].title.value, "Buổi training cho bài 2")
        XCTAssertEqual(
            calendar.dateComponents([.year, .month, .day], from: try XCTUnwrap(drafts[0].start.value)),
            DateComponents(year: 2026, month: 7, day: 19)
        )
        XCTAssertEqual(
            calendar.dateComponents([.year, .month, .day], from: try XCTUnwrap(drafts[1].start.value)),
            DateComponents(year: 2026, month: 7, day: 16)
        )
        XCTAssertTrue(drafts.allSatisfy(\.isAllDay))
        XCTAssertTrue(drafts.allSatisfy {
            $0.ambiguities.contains { ambiguity in
                ambiguity.field == .dateTime && ambiguity.message.contains("No clock time")
            }
        })
    }

    func testNumberedAgendaWithoutIndependentDatesRemainsOneEvent() throws {
        let extractor = LocalEventExtractor(calendar: calendar)
        let drafts = try extractor.extractEvents(
            lines: [
                RecognizedTextLine(text: "AI Workshop", confidence: 0.98),
                RecognizedTextLine(text: "20h ngày 15/08/2026", confidence: 0.96),
                RecognizedTextLine(text: "1) Welcome and check-in", confidence: 0.95),
                RecognizedTextLine(text: "2) Model building exercise", confidence: 0.95),
            ],
            capturedAt: makeDate(year: 2026, month: 7, day: 15, hour: 9),
            sourceFileName: "agenda.png"
        )

        XCTAssertEqual(drafts.count, 1)
        XCTAssertEqual(drafts[0].title.value, "AI Workshop")
    }

    private func region(y: Double, height: Double) -> TextRegion {
        TextRegion(x: 0.2, y: y, width: 0.6, height: height)
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
