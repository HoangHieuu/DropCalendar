import CryptoKit
import Foundation
import ImageIO

private struct CandidateRow: Decodable {
    let commonsTitle: String
    let localImage: String
    let imageSHA256: String

    enum CodingKeys: String, CodingKey {
        case commonsTitle = "commons_title"
        case localImage = "local_image"
        case imageSHA256 = "image_sha256"
    }
}

private struct OCRLine: Encodable {
    let text: String
    let confidence: Double
    let region: TextRegion?
}

private struct OCRResult: Encodable {
    let schemaVersion = 1
    let candidateID: String
    let commonsTitle: String
    let localImage: String
    let imageSHA256: String
    let outcome: String
    let lines: [OCRLine]
    let failureReason: String?
    let latencyMilliseconds: Double

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case candidateID = "candidate_id"
        case commonsTitle = "commons_title"
        case localImage = "local_image"
        case imageSHA256 = "image_sha256"
        case outcome, lines
        case failureReason = "failure_reason"
        case latencyMilliseconds = "latency_ms"
    }
}

private enum CandidateRunnerError: LocalizedError {
    case usage
    case invalidCandidateLine(Int)
    case unsafeImagePath(String)
    case unreadableImage(String)
    case hashMismatch(String)

    var errorDescription: String? {
        switch self {
        case .usage:
            return "Usage: SnapCalCandidateOCRRunner <candidates.jsonl> <ocr-results.jsonl>"
        case let .invalidCandidateLine(line):
            return "Candidate line \(line) is invalid."
        case let .unsafeImagePath(candidateID):
            return "Candidate \(candidateID) points outside its corpus directory."
        case let .unreadableImage(candidateID):
            return "Candidate \(candidateID) could not be decoded as an image."
        case let .hashMismatch(candidateID):
            return "Candidate \(candidateID) does not match its recorded SHA-256."
        }
    }
}

@main
private enum CandidateOCRRunner {
    static func main() async throws {
        guard CommandLine.arguments.count == 3 else {
            throw CandidateRunnerError.usage
        }

        let candidatesURL = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL
        let outputURL = URL(fileURLWithPath: CommandLine.arguments[2]).standardizedFileURL
        let corpusRoot = candidatesURL.deletingLastPathComponent().standardizedFileURL
        let rows = try loadCandidates(candidatesURL)
        let ocr = VisionOCRService()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var output = Data()

        for (index, row) in rows.enumerated() {
            let started = DispatchTime.now().uptimeNanoseconds
            let candidateID = "commons-\(row.imageSHA256.prefix(16))"
            let result: OCRResult
            do {
                let imageURL = try resolvedImageURL(
                    row.localImage,
                    corpusRoot: corpusRoot,
                    candidateID: candidateID
                )
                let image = try loadVerifiedImage(
                    imageURL,
                    expectedSHA256: row.imageSHA256,
                    candidateID: candidateID
                )
                let lines = try await ocr.recognizeText(in: image).map {
                    OCRLine(text: $0.text, confidence: $0.confidence, region: $0.region)
                }
                result = OCRResult(
                    candidateID: candidateID,
                    commonsTitle: row.commonsTitle,
                    localImage: row.localImage,
                    imageSHA256: row.imageSHA256,
                    outcome: "recognized",
                    lines: lines,
                    failureReason: nil,
                    latencyMilliseconds: elapsedMilliseconds(since: started)
                )
            } catch {
                result = OCRResult(
                    candidateID: candidateID,
                    commonsTitle: row.commonsTitle,
                    localImage: row.localImage,
                    imageSHA256: row.imageSHA256,
                    outcome: "failure",
                    lines: [],
                    failureReason: redactedFailureReason(error),
                    latencyMilliseconds: elapsedMilliseconds(since: started)
                )
            }

            output.append(try encoder.encode(result))
            output.append(0x0A)
            if (index + 1).isMultiple(of: 20) || index + 1 == rows.count {
                print("Locally scanned \(index + 1)/\(rows.count) benchmark candidates.")
            }
        }

        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try output.write(to: outputURL, options: .atomic)
        print("Local OCR results were written outside the repository to \(outputURL.path)")
    }

    private static func loadCandidates(_ url: URL) throws -> [CandidateRow] {
        let contents = try String(contentsOf: url, encoding: .utf8)
        let decoder = JSONDecoder()
        return try contents
            .split(whereSeparator: { $0.isNewline })
            .enumerated()
            .map { index, line in
                do {
                    return try decoder.decode(CandidateRow.self, from: Data(line.utf8))
                } catch {
                    throw CandidateRunnerError.invalidCandidateLine(index + 1)
                }
            }
    }

    private static func resolvedImageURL(
        _ relativePath: String,
        corpusRoot: URL,
        candidateID: String
    ) throws -> URL {
        let imageURL = corpusRoot.appendingPathComponent(relativePath).standardizedFileURL
        let rootPath = corpusRoot.path.hasSuffix("/") ? corpusRoot.path : corpusRoot.path + "/"
        guard imageURL.path.hasPrefix(rootPath) else {
            throw CandidateRunnerError.unsafeImagePath(candidateID)
        }
        return imageURL
    }

    private static func loadVerifiedImage(
        _ url: URL,
        expectedSHA256: String,
        candidateID: String
    ) throws -> CGImage {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
            throw CandidateRunnerError.unreadableImage(candidateID)
        }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard digest == expectedSHA256.lowercased() else {
            throw CandidateRunnerError.hashMismatch(candidateID)
        }
        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            CGImageSourceGetCount(source) > 0,
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw CandidateRunnerError.unreadableImage(candidateID)
        }
        return image
    }

    private static func redactedFailureReason(_ error: Error) -> String {
        switch error {
        case CandidateRunnerError.hashMismatch:
            return "hash_mismatch"
        case CandidateRunnerError.unsafeImagePath:
            return "unsafe_image_path"
        case let visionError as VisionOCRError where visionError == .noText:
            return "no_text"
        default:
            return "unreadable_or_ocr_failed"
        }
    }

    private static func elapsedMilliseconds(since start: UInt64) -> Double {
        let elapsed = DispatchTime.now().uptimeNanoseconds - start
        return Double(elapsed) / 1_000_000
    }
}
