import Foundation
import XCTest
@testable import SnapCal

final class ReminderPolicyTests: XCTestCase {
    func testGenericFutureEventGetsDayAndHourSuggestions() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let draft = makeDraft(start: now.addingTimeInterval(3 * 86_400))

        XCTAssertEqual(
            ReminderPolicy.suggestions(for: draft, now: now),
            [EventReminder(minutesBefore: 1_440), EventReminder(minutesBefore: 60)]
        )
    }

    func testSameDaySuggestionsRemoveAlreadyPastTrigger() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let draft = makeDraft(start: now.addingTimeInterval(30 * 60))

        XCTAssertEqual(
            ReminderPolicy.suggestions(for: draft, now: now),
            [EventReminder(minutesBefore: 15)]
        )
    }

    func testOnlineAndWorkshopPoliciesUseContext() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var online = makeDraft(start: now.addingTimeInterval(2 * 86_400))
        online.location.value = "Online qua Zoom"
        var workshop = makeDraft(start: now.addingTimeInterval(2 * 86_400))
        workshop.title.value = "Hội thảo AI Workshop"

        XCTAssertEqual(
            ReminderPolicy.suggestions(for: online, now: now),
            [EventReminder(minutesBefore: 30), EventReminder(minutesBefore: 5)]
        )
        XCTAssertEqual(
            ReminderPolicy.suggestions(for: workshop, now: now),
            [EventReminder(minutesBefore: 1_440), EventReminder(minutesBefore: 120)]
        )
    }

    func testAllDaySuggestionMapsToPreviousMorning() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var draft = makeDraft(start: now.addingTimeInterval(2 * 86_400))
        draft.isAllDay = true

        XCTAssertEqual(
            ReminderPolicy.suggestions(for: draft, now: now),
            [EventReminder(minutesBefore: 900)]
        )
        XCTAssertEqual(
            ReminderPolicy.label(for: 900, allDay: true),
            "1 day before at 9:00 AM"
        )
    }

    func testValidationEnforcesGoogleOverrideBoundaries() {
        XCTAssertThrowsError(try ReminderPolicy.validate(
            [0, 5, 15, 30, 60, 120].map { EventReminder(minutesBefore: $0) }
        )) { error in
            XCTAssertEqual(error as? ReminderValidationError, .tooMany)
        }
        XCTAssertThrowsError(try ReminderPolicy.validate([
            EventReminder(minutesBefore: 40_321)
        ])) { error in
            XCTAssertEqual(error as? ReminderValidationError, .outOfRange)
        }
        XCTAssertThrowsError(try ReminderPolicy.validate([
            EventReminder(minutesBefore: 15),
            EventReminder(minutesBefore: 15)
        ])) { error in
            XCTAssertEqual(error as? ReminderValidationError, .duplicate)
        }
    }

    private func makeDraft(start: Date) -> EventDraft {
        EventDraft(
            capturedAt: start,
            sourceFileName: "event.png",
            detectedLanguage: .mixed,
            rawOCRText: "Event",
            title: ExtractedField(value: "Community Event", evidenceText: "Event", confidence: 0.9),
            start: ExtractedField(value: start, evidenceText: "Tomorrow", confidence: 0.9),
            end: ExtractedField(value: start.addingTimeInterval(3_600), evidenceText: nil, confidence: 0.5),
            location: ExtractedField(value: "District 1", evidenceText: "D1", confidence: 0.8),
            description: ExtractedField(value: nil, evidenceText: nil, confidence: 0),
            ambiguities: []
        )
    }
}
