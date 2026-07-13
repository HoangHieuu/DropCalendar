import CoreGraphics
import Foundation
import Vision

struct TextRegion: Codable, Equatable, Sendable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

struct RecognizedTextLine: Equatable, Sendable {
    let text: String
    let confidence: Double
    let region: TextRegion?

    init(text: String, confidence: Double, region: TextRegion? = nil) {
        self.text = text
        self.confidence = confidence
        self.region = region
    }
}

protocol OCRRecognizing {
    func recognizeText(in image: CGImage) async throws -> [RecognizedTextLine]
}

enum VisionOCRError: LocalizedError, Equatable {
    case noText
    case recognitionFailed

    var errorDescription: String? {
        switch self {
        case .noText:
            return "No readable text was found in the screenshot."
        case .recognitionFailed:
            return "Apple Vision could not finish text recognition."
        }
    }
}

struct VisionOCRService: OCRRecognizing {
    func recognizeText(in image: CGImage) async throws -> [RecognizedTextLine] {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let request = VNRecognizeTextRequest()
                    request.recognitionLevel = .accurate
                    request.usesLanguageCorrection = true
                    request.minimumTextHeight = 0.008

                    let preferredLanguages = ["vi-VN", "en-US"]
                    let supportedLanguages = try request.supportedRecognitionLanguages()
                    request.recognitionLanguages = preferredLanguages.filter(
                        supportedLanguages.contains
                    )

                    let handler = VNImageRequestHandler(cgImage: image)
                    try handler.perform([request])

                    let observations = (request.results ?? []).sorted { left, right in
                        let verticalDelta = left.boundingBox.maxY - right.boundingBox.maxY
                        if abs(verticalDelta) > 0.015 {
                            return verticalDelta > 0
                        }
                        return left.boundingBox.minX < right.boundingBox.minX
                    }

                    let lines = observations.compactMap { observation -> RecognizedTextLine? in
                        guard let candidate = observation.topCandidates(1).first else {
                            return nil
                        }
                        let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !text.isEmpty else { return nil }
                        return RecognizedTextLine(
                            text: text,
                            confidence: Double(candidate.confidence),
                            region: TextRegion(
                                x: observation.boundingBox.minX,
                                y: observation.boundingBox.minY,
                                width: observation.boundingBox.width,
                                height: observation.boundingBox.height
                            )
                        )
                    }

                    guard !lines.isEmpty else {
                        continuation.resume(throwing: VisionOCRError.noText)
                        return
                    }
                    continuation.resume(returning: lines)
                } catch let error as VisionOCRError {
                    continuation.resume(throwing: error)
                } catch {
                    continuation.resume(throwing: VisionOCRError.recognitionFailed)
                }
            }
        }
    }
}
