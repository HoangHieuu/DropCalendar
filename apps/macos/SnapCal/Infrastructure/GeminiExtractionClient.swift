import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct AccuracyExtractionClient: CloudEventExtracting {
    private struct Request: Encodable {
        let schemaVersion = "1"
        let imageBase64: String
        let mimeType = "image/jpeg"
        let capturedAt: Date
        let timeZone: String
        let locale: String
        let ocrLines: [OCRLine]

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case imageBase64 = "image_base64"
            case mimeType = "mime_type"
            case capturedAt = "captured_at"
            case timeZone = "time_zone"
            case locale
            case ocrLines = "ocr_lines"
        }
    }

    private struct OCRLine: Encodable {
        let text: String
        let confidence: Double
        let box: TextRegion?
    }

    private struct Response: Decodable {
        let schemaVersion: String
        let model: String
        let events: [Event]

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case model
            case event, events
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            schemaVersion = try container.decode(String.self, forKey: .schemaVersion)
            model = try container.decode(String.self, forKey: .model)
            switch schemaVersion {
            case "1":
                events = [try container.decode(Event.self, forKey: .event)]
            case "2":
                events = try container.decode([Event].self, forKey: .events)
            default:
                throw DecodingError.dataCorruptedError(
                    forKey: .schemaVersion,
                    in: container,
                    debugDescription: "Unsupported extraction response schema"
                )
            }
        }
    }

    private struct ErrorResponse: Decodable {
        struct Detail: Decodable {
            let code: String
        }

        let detail: Detail
    }

    private struct Event: Decodable {
        let title: StringField
        let start: TemporalField
        let end: TemporalField
        let location: StringField
        let description: StringField
        let isAllDay: Bool
        let ambiguities: [Ambiguity]

        enum CodingKeys: String, CodingKey {
            case title, start, end, location, description, ambiguities
            case isAllDay = "is_all_day"
        }
    }

    private struct StringField: Decodable {
        let value: String?
        let evidenceText: String?
        let confidence: Double
        let isInferred: Bool

        enum CodingKeys: String, CodingKey {
            case value, confidence
            case evidenceText = "evidence_text"
            case isInferred = "is_inferred"
        }
    }

    private struct TemporalField: Decodable {
        let date: String?
        let time: String?
        let evidenceText: String?
        let confidence: Double
        let isInferred: Bool

        enum CodingKeys: String, CodingKey {
            case date, time, confidence
            case evidenceText = "evidence_text"
            case isInferred = "is_inferred"
        }
    }

    private struct Ambiguity: Decodable {
        let field: String
        let message: String
        let severity: String
    }

    private let endpoint: URL
    private let transport: any HTTPTransport
    private let calendar: Calendar
    private let timeZone: TimeZone
    private let locale: Locale

    init(
        endpoint: URL,
        transport: any HTTPTransport = URLSessionHTTPTransport(),
        calendar: Calendar = .current,
        timeZone: TimeZone = .current,
        locale: Locale = .current
    ) throws {
        guard Self.isAllowed(endpoint: endpoint) else {
            throw CloudExtractionError.invalidConfiguration
        }
        self.endpoint = endpoint
        self.transport = transport
        self.calendar = calendar
        self.timeZone = timeZone
        self.locale = locale
    }

    static func live() -> any CloudEventExtracting {
        let configured = ProcessInfo.processInfo.environment["SNAPCAL_EXTRACTION_API_URL"]
        let baseURL = configured.flatMap(URL.init(string:))
            ?? URL(string: "http://127.0.0.1:8765")!
        guard let endpoint = URL(string: "/v1/extract", relativeTo: baseURL)?.absoluteURL,
              let client = try? AccuracyExtractionClient(endpoint: endpoint) else {
            return DisabledCloudEventExtractor()
        }
        return client
    }

    func extract(
        image: ValidatedImage,
        lines: [RecognizedTextLine],
        capturedAt: Date,
        sourceFileName: String
    ) async throws -> CloudExtractionResult {
        let jpeg = try encodeJPEG(image.cgImage)
        let body = Request(
            imageBase64: jpeg.base64EncodedString(),
            capturedAt: capturedAt,
            timeZone: timeZone.identifier,
            locale: locale.identifier,
            ocrLines: lines.map {
                OCRLine(text: $0.text, confidence: $0.confidence, box: $0.region)
            }
        )

        var urlRequest = URLRequest(url: endpoint, timeoutInterval: 30)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        urlRequest.httpBody = try encoder.encode(body)

        let (data, response): (Data, HTTPURLResponse)
        do {
            (data, response) = try await transport.data(for: urlRequest)
        } catch {
            throw CloudExtractionError.unavailable
        }
        switch response.statusCode {
        case 200:
            break
        case 503:
            if errorCode(in: data) == "benchmark_preflight_failed" {
                throw CloudExtractionError.benchmarkPreflightFailed
            }
            throw CloudExtractionError.notConfigured
        case 422:
            throw CloudExtractionError.rejected
        case 402:
            throw CloudExtractionError.benchmarkBudgetExhausted
        case 502:
            switch errorCode(in: data) {
            case "benchmark_usage_unavailable":
                throw CloudExtractionError.benchmarkUsageUnavailable
            case "invalid_provider_output":
                throw CloudExtractionError.invalidResponse
            case "provider_rejected":
                throw CloudExtractionError.rejected
            default:
                throw CloudExtractionError.unavailable
            }
        default:
            throw CloudExtractionError.unavailable
        }
        guard data.count <= 1_000_000,
              let decoded = try? JSONDecoder().decode(Response.self, from: data),
              !decoded.model.isEmpty,
              (1...10).contains(decoded.events.count) else {
            throw CloudExtractionError.invalidResponse
        }
        return CloudExtractionResult(
            drafts: try decoded.events.map {
                try makeDraft(
                    from: $0,
                    lines: lines,
                    capturedAt: capturedAt,
                    sourceFileName: sourceFileName
                )
            },
            model: decoded.model
        )
    }

    private func makeDraft(
        from event: Event,
        lines: [RecognizedTextLine],
        capturedAt: Date,
        sourceFileName: String
    ) throws -> EventDraft {
        guard valid(event.title), valid(event.location), valid(event.description),
              valid(event.start), valid(event.end),
              let startDate = date(from: event.start, allDay: event.isAllDay) else {
            throw CloudExtractionError.invalidResponse
        }

        let endDate = date(from: event.end, allDay: event.isAllDay)
            ?? inferredEnd(from: startDate, title: event.title.value, allDay: event.isAllDay)
        guard let endDate, event.isAllDay ? endDate >= startDate : endDate > startDate else {
            throw CloudExtractionError.invalidResponse
        }

        let rawText = lines.map(\.text).joined(separator: "\n")
        var ambiguities = try event.ambiguities.map(makeAmbiguity)
        if event.end.date == nil {
            ambiguities.append(DraftAmbiguity(
                field: .endTime,
                message: "The end was estimated and should be reviewed.",
                severity: .medium
            ))
        }

        return EventDraft(
            capturedAt: capturedAt,
            sourceFileName: sourceFileName,
            detectedLanguage: detectedLanguage(in: rawText),
            rawOCRText: rawText,
            title: extracted(event.title),
            start: ExtractedField(
                value: startDate,
                evidenceText: event.start.evidenceText,
                confidence: event.start.confidence,
                isInferred: event.start.isInferred
            ),
            end: ExtractedField(
                value: endDate,
                evidenceText: event.end.evidenceText,
                confidence: event.end.date == nil ? 0.5 : event.end.confidence,
                isInferred: event.end.date == nil || event.end.isInferred
            ),
            location: extracted(event.location),
            description: extracted(event.description),
            isAllDay: event.isAllDay,
            ambiguities: ambiguities
        )
    }

    private func errorCode(in data: Data) -> String? {
        guard data.count <= 100_000 else { return nil }
        return try? JSONDecoder().decode(ErrorResponse.self, from: data).detail.code
    }

    private func valid(_ field: StringField) -> Bool {
        (0...1).contains(field.confidence) &&
            (field.value == nil || !(field.value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private func valid(_ field: TemporalField) -> Bool {
        (0...1).contains(field.confidence) &&
            (field.date == nil || !(field.evidenceText ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private func extracted(_ field: StringField) -> ExtractedField<String> {
        ExtractedField(
            value: field.value?.trimmingCharacters(in: .whitespacesAndNewlines),
            evidenceText: field.evidenceText,
            confidence: field.confidence,
            isInferred: field.isInferred
        )
    }

    private func date(from field: TemporalField, allDay: Bool) -> Date? {
        guard let day = parseDay(field.date) else { return nil }
        if allDay { return day }
        guard let time = parseTime(field.time) else { return nil }
        var localCalendar = calendar
        localCalendar.timeZone = timeZone
        var components = localCalendar.dateComponents([.year, .month, .day], from: day)
        components.hour = time.hour
        components.minute = time.minute
        components.second = time.second
        components.timeZone = timeZone
        return localCalendar.date(from: components)
    }

    private func parseDay(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter.date(from: value)
    }

    private func parseTime(_ value: String?) -> DateComponents? {
        guard let value else { return nil }
        let parts = value.split(separator: ":").compactMap { Int($0) }
        guard (2...3).contains(parts.count),
              (0...23).contains(parts[0]),
              (0...59).contains(parts[1]),
              parts.count < 3 || (0...59).contains(parts[2]) else {
            return nil
        }
        return DateComponents(
            hour: parts[0],
            minute: parts[1],
            second: parts.count == 3 ? parts[2] : 0
        )
    }

    private func inferredEnd(from start: Date, title: String?, allDay: Bool) -> Date? {
        if allDay { return start }
        let folded = (title ?? "").lowercased()
        let minutes = folded.contains("workshop") || folded.contains("meetup") ? 120 : 60
        return calendar.date(byAdding: .minute, value: minutes, to: start)
    }

    private func makeAmbiguity(_ ambiguity: Ambiguity) throws -> DraftAmbiguity {
        guard let field = AmbiguityField(rawValue: ambiguity.field),
              let severity = AmbiguitySeverity(rawValue: ambiguity.severity),
              !ambiguity.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CloudExtractionError.invalidResponse
        }
        return DraftAmbiguity(field: field, message: ambiguity.message, severity: severity)
    }

    private func detectedLanguage(in text: String) -> DraftLanguage {
        let lower = text.lowercased()
        let vietnamese = ["ngày", "thứ", "đại học", "quận", "giờ"].count(where: lower.contains)
        let english = ["workshop", "meetup", "july", "august", "university"].count(where: lower.contains)
        switch (vietnamese, english) {
        case (0, 0): return .unknown
        case let (v, e) where v > e: return .vietnamese
        case let (v, e) where e > v: return .english
        default: return .mixed
        }
    }

    private func encodeJPEG(_ image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw CloudExtractionError.imageEncodingFailed
        }
        CGImageDestinationAddImage(
            destination,
            image,
            [kCGImageDestinationLossyCompressionQuality: 0.86] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination),
              data.length > 0,
              data.length <= ImageValidator.maximumBytes else {
            throw CloudExtractionError.imageEncodingFailed
        }
        return data as Data
    }

    private static func isAllowed(endpoint: URL) -> Bool {
        guard let scheme = endpoint.scheme?.lowercased(), let host = endpoint.host?.lowercased() else {
            return false
        }
        if scheme == "https" { return true }
        return scheme == "http" && (host == "127.0.0.1" || host == "localhost")
    }
}
