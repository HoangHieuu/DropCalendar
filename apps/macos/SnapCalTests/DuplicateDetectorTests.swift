import Foundation
import XCTest
@testable import SnapCal

final class DuplicateDetectorTests: XCTestCase {
    func testExactFingerprintIsHighConfidenceDuplicate() {
        let candidate = signature(id: UUID(), fingerprint: "abc", title: "Event")
        let existing = signature(id: UUID(), fingerprint: "abc", title: "Different")

        let warnings = DuplicateDetector.warnings(for: candidate, among: [existing])

        XCTAssertEqual(warnings.first?.kind, .sameScreenshot)
        XCTAssertEqual(warnings.first?.severity, .high)
    }

    func testNormalizedTitleAndStartDetectsVietnameseEquivalent() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let candidate = signature(id: UUID(), title: "Hội thảo AI!", start: start)
        let existing = signature(
            id: UUID(),
            title: "HOI THAO AI",
            start: start.addingTimeInterval(120)
        )

        XCTAssertEqual(
            DuplicateDetector.warnings(for: candidate, among: [existing]).first?.kind,
            .sameTitleAndTime
        )
    }

    func testSameTitleDateAndLocationIsSoftWarning() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")!
        let start = calendar.date(from: DateComponents(year: 2026, month: 8, day: 15, hour: 9))!
        let candidate = signature(
            id: UUID(),
            title: "AI Meetup",
            start: start,
            location: "Quận 1, TP.HCM"
        )
        let existing = signature(
            id: UUID(),
            title: "ai meetup",
            start: start.addingTimeInterval(8 * 3_600),
            location: "Quan 1 TP HCM"
        )

        let warning = DuplicateDetector.warnings(
            for: candidate,
            among: [existing],
            calendar: calendar
        ).first

        XCTAssertEqual(warning?.kind, .sameTitleDateAndLocation)
        XCTAssertEqual(warning?.severity, .soft)
    }

    func testUnrelatedHistoryDoesNotWarn() {
        let candidate = signature(id: UUID(), title: "AI Meetup")
        let existing = signature(id: UUID(), title: "Concert")
        XCTAssertTrue(DuplicateDetector.warnings(for: candidate, among: [existing]).isEmpty)
    }

    func testOnlineLocationNormalizesAndPreservesMeetingDetails() {
        var draft = makeDraft(location: "Online qua Zoom: zoom.us/j/123")

        LocationNormalizer.normalize(&draft)

        XCTAssertEqual(draft.location.value, "Online")
        XCTAssertTrue(draft.description.value?.contains("zoom.us/j/123") == true)
        XCTAssertEqual(draft.location.evidenceText, "Online qua Zoom: zoom.us/j/123")
    }

    private func signature(
        id: UUID,
        fingerprint: String? = nil,
        title: String? = nil,
        start: Date? = nil,
        location: String? = nil
    ) -> DuplicateSignature {
        DuplicateSignature(
            id: id,
            sourceFingerprint: fingerprint,
            title: title,
            start: start,
            location: location
        )
    }

    private func makeDraft(location: String) -> EventDraft {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        return EventDraft(
            capturedAt: start,
            sourceFileName: "event.png",
            detectedLanguage: .mixed,
            rawOCRText: location,
            title: ExtractedField(value: "Event", evidenceText: "Event", confidence: 0.9),
            start: ExtractedField(value: start, evidenceText: "Date", confidence: 0.9),
            end: ExtractedField(value: start.addingTimeInterval(3_600), evidenceText: nil, confidence: 0.5),
            location: ExtractedField(value: location, evidenceText: location, confidence: 0.9),
            description: ExtractedField(value: nil, evidenceText: nil, confidence: 0),
            ambiguities: []
        )
    }
}
