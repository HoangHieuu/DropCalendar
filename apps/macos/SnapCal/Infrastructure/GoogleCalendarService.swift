import Foundation

struct GoogleCalendarEventPayload: Encodable, Equatable {
    struct Boundary: Encodable, Equatable {
        let dateTime: String?
        let date: String?
        let timeZone: String?

        init(dateTime: String? = nil, date: String? = nil, timeZone: String? = nil) {
            self.dateTime = dateTime
            self.date = date
            self.timeZone = timeZone
        }
    }

    let summary: String
    let location: String?
    let description: String?
    let start: Boundary
    let end: Boundary

    static func make(from request: CalendarEventRequest) -> GoogleCalendarEventPayload {
        let start: Boundary
        let end: Boundary

        switch request.timing {
        case .timed(let startDate, let endDate, let timeZone):
            start = Boundary(
                dateTime: RFC3339.string(from: startDate),
                timeZone: timeZone.identifier
            )
            end = Boundary(
                dateTime: RFC3339.string(from: endDate),
                timeZone: timeZone.identifier
            )
        case .allDay(let startDate, let endExclusive, let timeZone):
            start = Boundary(date: DayString.string(from: startDate, timeZone: timeZone))
            end = Boundary(date: DayString.string(from: endExclusive, timeZone: timeZone))
        }

        return GoogleCalendarEventPayload(
            summary: request.summary,
            location: request.location,
            description: request.description,
            start: start,
            end: end
        )
    }
}

private enum RFC3339 {
    static func string(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}

private enum DayString {
    static func string(from date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

struct GoogleCalendarClient: Sendable {
    private struct ProviderResponse: Decodable {
        let id: String
        let htmlLink: String?
    }

    private let endpoint: URL
    private let transport: any HTTPTransport

    init(
        endpoint: URL = URL(string: "https://www.googleapis.com/calendar/v3/calendars/primary/events")!,
        transport: any HTTPTransport = URLSessionHTTPTransport()
    ) {
        self.endpoint = endpoint
        self.transport = transport
    }

    func createEvent(
        _ eventRequest: CalendarEventRequest,
        accessToken: String
    ) async throws -> CalendarCreationReceipt {
        let payload = GoogleCalendarEventPayload.make(from: eventRequest)
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await transport.data(for: request)
        switch response.statusCode {
        case 200..<300:
            break
        case 401:
            throw GoogleCalendarError.notAuthorized
        case 429:
            throw GoogleCalendarError.rateLimited
        default:
            throw GoogleCalendarError.providerRejected
        }

        guard let providerResponse = try? JSONDecoder().decode(ProviderResponse.self, from: data),
              !providerResponse.id.isEmpty else {
            throw GoogleCalendarError.invalidProviderResponse
        }
        let link = providerResponse.htmlLink
            .flatMap(URL.init(string:))
            .flatMap { $0.scheme?.lowercased() == "https" ? $0 : nil }
        return CalendarCreationReceipt(
            providerEventID: providerResponse.id,
            calendarLink: link
        )
    }
}

actor GoogleCalendarScheduler: CalendarScheduling {
    private let oauth: GoogleOAuthService
    private let calendarClient: GoogleCalendarClient

    init(oauth: GoogleOAuthService, calendarClient: GoogleCalendarClient) {
        self.oauth = oauth
        self.calendarClient = calendarClient
    }

    static func live() -> GoogleCalendarScheduler {
        let configuration = GoogleOAuthConfiguration.live
        let store = KeychainCredentialStore(account: configuration.clientID)
        return GoogleCalendarScheduler(
            oauth: GoogleOAuthService(
                configuration: configuration,
                credentialStore: store
            ),
            calendarClient: GoogleCalendarClient()
        )
    }

    func hasStoredAuthorization() async -> Bool {
        await oauth.hasStoredAuthorization()
    }

    func createEvent(from request: CalendarEventRequest) async throws -> CalendarCreationReceipt {
        let accessToken = try await oauth.validAccessToken()
        return try await calendarClient.createEvent(request, accessToken: accessToken)
    }

    func disconnect() async throws {
        try await oauth.disconnect()
    }
}
