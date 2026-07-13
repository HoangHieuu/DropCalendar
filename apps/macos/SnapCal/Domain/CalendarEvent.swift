import Foundation

struct CalendarCreationReceipt: Equatable {
    let providerEventID: String
    let calendarLink: URL?
}

enum CalendarCreationState: Equatable {
    case idle
    case awaitingConfirmation
    case authorizing
    case creating
    case created(CalendarCreationReceipt)
    case failed(CalendarCreationIssue)
}

struct CalendarCreationIssue: Equatable {
    let title: String
    let message: String

    init(title: String, message: String) {
        self.title = title
        self.message = message
    }

    init(error: Error) {
        switch error {
        case GoogleCalendarError.authorizationCancelled:
            title = "Google connection cancelled"
            message = "Your draft is unchanged. Confirm Create Event when you are ready to try again."
        case GoogleCalendarError.authorizationDenied:
            title = "Calendar permission denied"
            message = "SnapCal needs permission to create events in a Google Calendar you own."
        case GoogleCalendarError.authorizationTimedOut:
            title = "Google connection timed out"
            message = "Your draft is unchanged. Review and confirm again when you are ready to sign in."
        case GoogleCalendarError.invalidDraft(let reason):
            title = "Review required"
            message = reason
        case GoogleCalendarError.rateLimited:
            title = "Google Calendar is busy"
            message = "Please wait a moment, then review and confirm the event again."
        case GoogleCalendarError.notAuthorized:
            title = "Google connection expired"
            message = "Review and confirm again to reconnect your Google Calendar."
        case GoogleCalendarError.providerRejected:
            title = "Google Calendar rejected the event"
            message = "Your draft is preserved. Check the event details, then try again."
        default:
            title = "Calendar creation failed"
            message = "Your draft is preserved. Review it and try again."
        }
    }
}

enum GoogleCalendarError: Error, Equatable {
    case invalidConfiguration
    case invalidDraft(String)
    case authorizationCancelled
    case authorizationDenied
    case authorizationTimedOut
    case invalidAuthorizationResponse
    case stateMismatch
    case tokenExchangeFailed
    case notAuthorized
    case rateLimited
    case providerRejected
    case invalidProviderResponse
    case keychainFailure
    case callbackFailed
}

struct CalendarEventRequest: Equatable {
    enum Timing: Equatable {
        case timed(start: Date, end: Date, timeZone: TimeZone)
        case allDay(start: Date, endExclusive: Date, timeZone: TimeZone)
    }

    let summary: String
    let location: String?
    let description: String?
    let timing: Timing
}

enum CalendarEventMapper {
    static func request(
        from draft: EventDraft,
        timeZone: TimeZone = .current,
        calendar: Calendar = .current
    ) throws -> CalendarEventRequest {
        let summary = (draft.title.value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !summary.isEmpty else {
            throw GoogleCalendarError.invalidDraft("Enter an event title before creating the event.")
        }
        guard let start = draft.start.value else {
            throw GoogleCalendarError.invalidDraft("Choose the event start date and time.")
        }
        guard let end = draft.end.value else {
            throw GoogleCalendarError.invalidDraft("Choose an end after the event start.")
        }
        guard draft.isAllDay ? end >= start : end > start else {
            throw GoogleCalendarError.invalidDraft("Choose an end after the event start.")
        }

        let timing: CalendarEventRequest.Timing
        if draft.isAllDay {
            var localCalendar = calendar
            localCalendar.timeZone = timeZone
            let startDay = localCalendar.startOfDay(for: start)
            let selectedEndDay = localCalendar.startOfDay(for: end)
            let endExclusive = selectedEndDay > startDay
                ? selectedEndDay
                : localCalendar.date(byAdding: .day, value: 1, to: startDay)!
            timing = .allDay(start: startDay, endExclusive: endExclusive, timeZone: timeZone)
        } else {
            timing = .timed(start: start, end: end, timeZone: timeZone)
        }

        return CalendarEventRequest(
            summary: summary,
            location: nonEmpty(draft.location.value),
            description: nonEmpty(draft.description.value),
            timing: timing
        )
    }

    private static func nonEmpty(_ value: String?) -> String? {
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

protocol CalendarScheduling: Sendable {
    func hasStoredAuthorization() async -> Bool
    func createEvent(from request: CalendarEventRequest) async throws -> CalendarCreationReceipt
    func disconnect() async throws
}

struct DisabledCalendarScheduler: CalendarScheduling {
    func hasStoredAuthorization() async -> Bool { false }

    func createEvent(from request: CalendarEventRequest) async throws -> CalendarCreationReceipt {
        throw GoogleCalendarError.invalidConfiguration
    }

    func disconnect() async throws { }
}
