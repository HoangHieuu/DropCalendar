import Foundation

private struct AccuracyManifestRow: Decodable {
    let id: String
    let image: String
    let language: String
    let capturedAt: String
    let timezone: String

    enum CodingKeys: String, CodingKey {
        case id, image, language, timezone
        case capturedAt = "captured_at"
    }
}

private enum AccuracyRunnerError: LocalizedError {
    case usage
    case invalidManifestLine(Int)
    case invalidCaptureTime(String)
    case invalidTimeZone(String)
    case invalidEndpoint

    var errorDescription: String? {
        switch self {
        case .usage:
            return "Usage: SnapCalAccuracyBenchmarkRunner <manifest.jsonl> <predictions.jsonl> <extract-endpoint>"
        case let .invalidManifestLine(line):
            return "Manifest line \(line) is invalid."
        case let .invalidCaptureTime(itemID):
            return "Fixture \(itemID) has an invalid capture time."
        case let .invalidTimeZone(itemID):
            return "Fixture \(itemID) has an invalid timezone."
        case .invalidEndpoint:
            return "The Accuracy Mode benchmark endpoint is invalid."
        }
    }
}

@main
private enum AccuracyBenchmarkRunner {
    static func main() async throws {
        guard CommandLine.arguments.count == 4 else {
            throw AccuracyRunnerError.usage
        }
        let manifestURL = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL
        let outputURL = URL(fileURLWithPath: CommandLine.arguments[2]).standardizedFileURL
        guard let endpoint = URL(string: CommandLine.arguments[3]) else {
            throw AccuracyRunnerError.invalidEndpoint
        }
        let rows = try loadManifest(manifestURL)
        let corpusRoot = manifestURL.deletingLastPathComponent()
        let validator = ImageValidator()
        let ocr = VisionOCRService()
        var output = Data()

        for row in rows {
            let started = DispatchTime.now().uptimeNanoseconds
            let prediction: [String: Any]
            do {
                let capturedAt = try parseCaptureTime(row.capturedAt, itemID: row.id)
                guard let timeZone = TimeZone(identifier: row.timezone) else {
                    throw AccuracyRunnerError.invalidTimeZone(row.id)
                }
                let imageURL = corpusRoot.appendingPathComponent(row.image).standardizedFileURL
                let image = try validator.validate(imageURL)
                let lines = try await ocr.recognizeText(in: image.cgImage)
                let client = try AccuracyExtractionClient(
                    endpoint: endpoint,
                    timeZone: timeZone,
                    locale: locale(for: row.language)
                )
                let result = try await client.extract(
                    image: image,
                    lines: lines,
                    capturedAt: capturedAt,
                    sourceFileName: imageURL.lastPathComponent
                )
                prediction = draftPrediction(
                    itemID: row.id,
                    draft: result.draft,
                    timeZone: timeZone,
                    latencyMilliseconds: elapsedMilliseconds(since: started)
                )
            } catch {
                prediction = failurePrediction(
                    itemID: row.id,
                    error: error,
                    latencyMilliseconds: elapsedMilliseconds(since: started)
                )
            }
            output.append(try JSONSerialization.data(
                withJSONObject: prediction,
                options: [.sortedKeys, .withoutEscapingSlashes]
            ))
            output.append(0x0A)
        }

        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try output.write(to: outputURL, options: .atomic)
        print("Accuracy Mode benchmark wrote \(rows.count) redacted predictions to \(outputURL.path)")
    }

    private static func loadManifest(_ url: URL) throws -> [AccuracyManifestRow] {
        let contents = try String(contentsOf: url, encoding: .utf8)
        let decoder = JSONDecoder()
        return try contents
            .split(whereSeparator: { $0.isNewline })
            .enumerated()
            .map { index, line in
                do {
                    return try decoder.decode(AccuracyManifestRow.self, from: Data(line.utf8))
                } catch {
                    throw AccuracyRunnerError.invalidManifestLine(index + 1)
                }
            }
    }

    private static func parseCaptureTime(_ value: String, itemID: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withColonSeparatorInTimeZone]
        guard let date = formatter.date(from: value) else {
            throw AccuracyRunnerError.invalidCaptureTime(itemID)
        }
        return date
    }

    private static func locale(for language: String) -> Locale {
        language == "english" ? Locale(identifier: "en_US") : Locale(identifier: "vi_VN")
    }

    private static func draftPrediction(
        itemID: String,
        draft: EventDraft,
        timeZone: TimeZone,
        latencyMilliseconds: Double
    ) -> [String: Any] {
        var evidence: [String] = []
        if draft.title.evidenceText?.isEmpty == false { evidence.append("title") }
        if draft.start.evidenceText?.isEmpty == false { evidence.append("start") }
        if draft.location.evidenceText?.isEmpty == false { evidence.append("location") }
        return [
            "schema_version": 1,
            "item_id": itemID,
            "mode": "accuracy",
            "outcome": "draft",
            "title": draft.title.value ?? NSNull(),
            "start": formatted(draft.start.value, allDay: draft.isAllDay, timeZone: timeZone),
            "end": formatted(draft.end.value, allDay: draft.isAllDay, timeZone: timeZone),
            "is_all_day": draft.isAllDay,
            "location": draft.location.value ?? NSNull(),
            "evidence_fields": evidence,
            "ambiguity_fields": draft.ambiguities.map(\.field.rawValue),
            "latency_ms": latencyMilliseconds,
            "failure_reason": NSNull(),
        ]
    }

    private static func failurePrediction(
        itemID: String,
        error: Error,
        latencyMilliseconds: Double
    ) -> [String: Any] {
        let reason: String
        switch error {
        case CloudExtractionError.noEventDetected:
            reason = "no_event_detected"
        case CloudExtractionError.rejected:
            reason = "provider_rejected_input"
        case CloudExtractionError.invalidResponse:
            reason = "invalid_provider_output"
        case CloudExtractionError.unavailable, CloudExtractionError.notConfigured:
            reason = "provider_unavailable"
        case ImageValidationError.unsupportedFormat:
            reason = "unsupported_image"
        case ImageValidationError.corruptImage:
            reason = "corrupt_image"
        default:
            reason = "insufficient_event_evidence"
        }
        return [
            "schema_version": 1,
            "item_id": itemID,
            "mode": "accuracy",
            "outcome": "failure",
            "title": NSNull(),
            "start": NSNull(),
            "end": NSNull(),
            "is_all_day": NSNull(),
            "location": NSNull(),
            "evidence_fields": [],
            "ambiguity_fields": ["extraction"],
            "latency_ms": latencyMilliseconds,
            "failure_reason": reason,
        ]
    }

    private static func formatted(_ value: Date?, allDay: Bool, timeZone: TimeZone) -> Any {
        guard let value else { return NSNull() }
        if allDay {
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = timeZone
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.string(from: value)
        }
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = timeZone
        formatter.formatOptions = [.withInternetDateTime, .withColonSeparatorInTimeZone]
        return formatter.string(from: value)
    }

    private static func elapsedMilliseconds(since start: UInt64) -> Double {
        let elapsed = DispatchTime.now().uptimeNanoseconds - start
        return Double(elapsed) / 1_000_000
    }
}
