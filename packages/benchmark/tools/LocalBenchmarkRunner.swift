import AppKit
import Foundation

private struct ManifestRow: Decodable {
    let id: String
    let image: String
    let capturedAt: String
    let timezone: String

    enum CodingKeys: String, CodingKey {
        case id, image, timezone
        case capturedAt = "captured_at"
    }
}

private enum RunnerError: LocalizedError {
    case usage
    case invalidManifestLine(Int)
    case invalidCaptureTime(String)
    case unreadableImage(String)

    var errorDescription: String? {
        switch self {
        case .usage:
            return "Usage: SnapCalLocalBenchmarkRunner <manifest.jsonl> <predictions.jsonl>"
        case let .invalidManifestLine(line):
            return "Manifest line \(line) is invalid."
        case let .invalidCaptureTime(itemID):
            return "Fixture \(itemID) has an invalid capture time."
        case let .unreadableImage(itemID):
            return "Fixture \(itemID) could not be decoded as an image."
        }
    }
}

@main
private enum LocalBenchmarkRunner {
    static func main() async throws {
        guard CommandLine.arguments.count == 3 else {
            throw RunnerError.usage
        }
        let manifestURL = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL
        let outputURL = URL(fileURLWithPath: CommandLine.arguments[2]).standardizedFileURL
        let rows = try loadManifest(manifestURL)
        let corpusRoot = manifestURL.deletingLastPathComponent()
        let ocr = VisionOCRService()
        var output = Data()

        for row in rows {
            let started = DispatchTime.now().uptimeNanoseconds
            let prediction: [String: Any]
            do {
                let capturedAt = try parseCaptureTime(row.capturedAt, itemID: row.id)
                let imageURL = corpusRoot.appendingPathComponent(row.image).standardizedFileURL
                let image = try loadCGImage(imageURL, itemID: row.id)
                let lines = try await ocr.recognizeText(in: image)
                var calendar = Calendar(identifier: .gregorian)
                guard let timeZone = TimeZone(identifier: row.timezone) else {
                    throw RunnerError.invalidCaptureTime(row.id)
                }
                calendar.timeZone = timeZone
                let extractor = LocalEventExtractor(calendar: calendar)
                let draft = try extractor.extract(
                    lines: lines,
                    capturedAt: capturedAt,
                    sourceFileName: imageURL.lastPathComponent
                )
                prediction = draftPrediction(
                    itemID: row.id,
                    draft: draft,
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
        print("Local Only benchmark wrote \(rows.count) redacted predictions to \(outputURL.path)")
    }

    private static func loadManifest(_ url: URL) throws -> [ManifestRow] {
        let contents = try String(contentsOf: url, encoding: .utf8)
        let decoder = JSONDecoder()
        return try contents
            .split(whereSeparator: { $0.isNewline })
            .enumerated()
            .map { index, line in
                do {
                    return try decoder.decode(ManifestRow.self, from: Data(line.utf8))
                } catch {
                    throw RunnerError.invalidManifestLine(index + 1)
                }
            }
    }

    private static func parseCaptureTime(_ value: String, itemID: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withColonSeparatorInTimeZone]
        guard let date = formatter.date(from: value) else {
            throw RunnerError.invalidCaptureTime(itemID)
        }
        return date
    }

    private static func loadCGImage(_ url: URL, itemID: String) throws -> CGImage {
        guard let image = NSImage(contentsOf: url) else {
            throw RunnerError.unreadableImage(itemID)
        }
        var rect = NSRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
            throw RunnerError.unreadableImage(itemID)
        }
        return cgImage
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
            "mode": "local_only",
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
        case is DraftExtractionError:
            reason = "no_event_detected"
        case let ocrError as VisionOCRError where ocrError == .noText:
            reason = "no_event_detected"
        default:
            reason = "insufficient_event_evidence"
        }
        return [
            "schema_version": 1,
            "item_id": itemID,
            "mode": "local_only",
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
