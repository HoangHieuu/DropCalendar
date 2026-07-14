import AppKit
import XCTest
@testable import SnapCal

final class AccuracyExtractionClientTests: XCTestCase {
    func testExtractSendsImageAndLayoutWithoutAnyCredentialAndBuildsAllDayDraft() async throws {
        let response = try XCTUnwrap(HTTPURLResponse(
            url: URL(string: "http://127.0.0.1:8765/v1/extract")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        ))
        let transport = AccuracyRecordingTransport(data: Data(validResponse.utf8), response: response)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")!
        let client = try AccuracyExtractionClient(
            endpoint: URL(string: "http://127.0.0.1:8765/v1/extract")!,
            transport: transport,
            calendar: calendar,
            timeZone: calendar.timeZone,
            locale: Locale(identifier: "en_VN")
        )
        let capturedAt = Date(timeIntervalSince1970: 1_783_930_400)
        let image = try makeValidatedImage(capturedAt: capturedAt)
        let lines = [
            RecognizedTextLine(
                text: "AGENTIC AI",
                confidence: 0.96,
                region: TextRegion(x: 0.2, y: 0.68, width: 0.6, height: 0.1)
            ),
            RecognizedTextLine(
                text: "July 8 - July 12, 2026",
                confidence: 0.94,
                region: TextRegion(x: 0.28, y: 0.42, width: 0.5, height: 0.04)
            )
        ]

        let result = try await client.extract(
            image: image,
            lines: lines,
            capturedAt: capturedAt,
            sourceFileName: "poster.jpg"
        )
        let capturedRequest = await transport.capturedRequest()
        let request = try XCTUnwrap(capturedRequest)
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let encodedLines = try XCTUnwrap(json["ocr_lines"] as? [[String: Any]])

        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(request.value(forHTTPHeaderField: "x-goog-api-key"))
        XCTAssertEqual(json["schema_version"] as? String, "1")
        XCTAssertFalse((json["image_base64"] as? String ?? "").isEmpty)
        XCTAssertNotNil(encodedLines.first?["box"])
        XCTAssertEqual(result.model, "google/gemini-3.1-flash-lite")
        XCTAssertEqual(result.draft.title.value, "Agentic AI Build Week")
        XCTAssertTrue(result.draft.isAllDay)
        XCTAssertEqual(calendar.component(.day, from: try XCTUnwrap(result.draft.start.value)), 8)
        XCTAssertEqual(calendar.component(.day, from: try XCTUnwrap(result.draft.end.value)), 12)
    }

    func testRejectsInsecureRemoteHTTPService() {
        XCTAssertThrowsError(
            try AccuracyExtractionClient(endpoint: URL(string: "http://example.com/v1/extract")!)
        ) { error in
            XCTAssertEqual(error as? CloudExtractionError, .invalidConfiguration)
        }
    }

    func testRejectsReversedProviderDateRange() async throws {
        let response = try XCTUnwrap(HTTPURLResponse(
            url: URL(string: "http://localhost:8765/v1/extract")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        ))
        let reversed = validResponse
            .replacingOccurrences(of: #""date":"2026-07-08""#, with: #""date":"2026-07-13""#)
        let transport = AccuracyRecordingTransport(data: Data(reversed.utf8), response: response)
        let client = try AccuracyExtractionClient(
            endpoint: URL(string: "http://localhost:8765/v1/extract")!,
            transport: transport
        )

        do {
            _ = try await client.extract(
                image: try makeValidatedImage(capturedAt: Date()),
                lines: [RecognizedTextLine(text: "Poster", confidence: 0.9)],
                capturedAt: Date(),
                sourceFileName: "poster.jpg"
            )
            XCTFail("Expected a reversed range to be rejected")
        } catch {
            XCTAssertEqual(error as? CloudExtractionError, .invalidResponse)
        }
    }

    private var validResponse: String {
        #"{"schema_version":"1","model":"google/gemini-3.1-flash-lite","event":{"title":{"value":"Agentic AI Build Week","evidence_text":"AGENTIC AI BUILD WEEK","confidence":0.98,"is_inferred":false},"start":{"date":"2026-07-08","time":null,"evidence_text":"July 8 - July 12, 2026","confidence":0.98,"is_inferred":false},"end":{"date":"2026-07-12","time":null,"evidence_text":"July 8 - July 12, 2026","confidence":0.98,"is_inferred":false},"location":{"value":"Ho Chi Minh, Vietnam","evidence_text":"Ho Chi Minh, Vietnam","confidence":0.97,"is_inferred":false},"description":{"value":"5 Days (Workshops + Hackathon)","evidence_text":"5 Days (Workshops + Hackathon)","confidence":0.94,"is_inferred":false},"is_all_day":true,"ambiguities":[]}}"#
    }

    private func makeValidatedImage(capturedAt: Date) throws -> ValidatedImage {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 2,
            pixelsHigh: 2,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        return ValidatedImage(
            cgImage: try XCTUnwrap(bitmap.cgImage),
            fileName: "poster.jpg",
            capturedAt: capturedAt
        )
    }
}

private actor AccuracyRecordingTransport: HTTPTransport {
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
