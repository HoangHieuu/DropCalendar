import Foundation
import XCTest
@testable import SnapCal

final class GoogleCalendarClientTests: XCTestCase {
    func testCreateEventUsesPrimaryCalendarBearerTokenAndReviewedPayload() async throws {
        let response = try XCTUnwrap(HTTPURLResponse(
            url: URL(string: "https://example.test")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        ))
        let transport = RecordingTransport(
            data: Data(#"{"id":"provider-123","htmlLink":"https://calendar.google.com/event?eid=abc"}"#.utf8),
            response: response
        )
        let client = GoogleCalendarClient(transport: transport)
        let start = Date(timeIntervalSince1970: 1_787_415_400)
        let request = CalendarEventRequest(
            summary: "AI Workshop",
            location: "District 1",
            description: nil,
            timing: .timed(
                start: start,
                end: start.addingTimeInterval(3_600),
                timeZone: TimeZone(identifier: "Asia/Ho_Chi_Minh")!
            )
        )

        let receipt = try await client.createEvent(request, accessToken: "access-token")
        let recordedRequest = await transport.capturedRequest()
        let captured = try XCTUnwrap(recordedRequest)

        XCTAssertEqual(captured.url?.absoluteString, "https://www.googleapis.com/calendar/v3/calendars/primary/events")
        XCTAssertEqual(captured.httpMethod, "POST")
        XCTAssertEqual(captured.value(forHTTPHeaderField: "Authorization"), "Bearer access-token")
        let body = try XCTUnwrap(captured.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["summary"] as? String, "AI Workshop")
        XCTAssertEqual(receipt.providerEventID, "provider-123")
        XCTAssertEqual(receipt.calendarLink?.scheme, "https")
    }

    func testCreateEventMapsUnauthorizedAndRateLimit() async throws {
        for (status, expectedError) in [(401, GoogleCalendarError.notAuthorized), (429, .rateLimited)] {
            let response = try XCTUnwrap(HTTPURLResponse(
                url: URL(string: "https://example.test")!,
                statusCode: status,
                httpVersion: nil,
                headerFields: nil
            ))
            let transport = RecordingTransport(data: Data(), response: response)
            let client = GoogleCalendarClient(transport: transport)
            let request = CalendarEventRequest(
                summary: "Event",
                location: nil,
                description: nil,
                timing: .timed(start: Date(), end: Date().addingTimeInterval(60), timeZone: .current)
            )

            do {
                _ = try await client.createEvent(request, accessToken: "token")
                XCTFail("Expected status \(status) to fail")
            } catch {
                XCTAssertEqual(error as? GoogleCalendarError, expectedError)
            }
        }
    }
}

private actor RecordingTransport: HTTPTransport {
    private let data: Data
    private let response: HTTPURLResponse
    private var request: URLRequest?

    init(data: Data, response: HTTPURLResponse) {
        self.data = data
        self.response = response
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        self.request = request
        return (data, response)
    }

    func capturedRequest() -> URLRequest? { request }
}
