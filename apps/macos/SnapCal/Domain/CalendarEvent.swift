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
        case GoogleCalendarError.oauthBrokerUnavailable:
            title = "Google connection helper is unavailable"
            message = "Start SnapCal's local service and configure its Google OAuth credential file, then review and confirm again."
        case GoogleCalendarError.hostedOAuthUnavailable:
            title = "SnapCal connection is unavailable"
            message = "Your Google connection and draft are preserved. Check your network, then review and confirm again."
        case GoogleCalendarError.oauthCredentialMismatch:
            title = "Google OAuth setup does not match"
            message = "The local service is using a different Google OAuth client. Check GOOGLE_OAUTH_CREDENTIALS_FILE, then try again."
        case GoogleCalendarError.tokenExchangeFailed:
            title = "Google sign-in could not finish"
            message = "Google rejected the connection after sign-in. Your draft is preserved; review and confirm again."
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
    case oauthBrokerUnavailable
    case hostedOAuthUnavailable
    case oauthCredentialMismatch
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
    let reminders: [EventReminder]

    init(
        summary: String,
        location: String?,
        description: String?,
        timing: Timing,
        reminders: [EventReminder] = []
    ) {
        self.summary = summary
        self.location = location
        self.description = description
        self.timing = timing
        self.reminders = reminders
    }
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
        do {
            try ReminderPolicy.validate(draft.reminders)
        } catch ReminderValidationError.tooMany {
            throw GoogleCalendarError.invalidDraft(
                "Google Calendar allows at most five reminder overrides. Remove a reminder before creating the event."
            )
        } catch ReminderValidationError.outOfRange {
            throw GoogleCalendarError.invalidDraft(
                "Choose reminders between the event time and four weeks before it."
            )
        } catch {
            throw GoogleCalendarError.invalidDraft(
                "Remove duplicate reminder choices before creating the event."
            )
        }

        let timing: CalendarEventRequest.Timing
        if draft.isAllDay {
            var localCalendar = calendar
            localCalendar.timeZone = timeZone
            let startDay = localCalendar.startOfDay(for: start)
            let selectedEndDay = localCalendar.startOfDay(for: end)
            let inclusiveEndDay = max(selectedEndDay, startDay)
            let endExclusive = localCalendar.date(byAdding: .day, value: 1, to: inclusiveEndDay)!
            timing = .allDay(start: startDay, endExclusive: endExclusive, timeZone: timeZone)
        } else {
            timing = .timed(start: start, end: end, timeZone: timeZone)
        }

        return CalendarEventRequest(
            summary: summary,
            location: nonEmpty(draft.location.value),
            description: nonEmpty(draft.description.value),
            timing: timing,
            reminders: draft.reminders
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
