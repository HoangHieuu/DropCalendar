import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct PreparedAccuracyImage: Equatable, Sendable {
    let jpegData: Data
    let pixelWidth: Int
    let pixelHeight: Int
}

protocol OptimizedCloudEventExtracting: CloudEventExtracting {
    func prepare(image: ValidatedImage) async throws -> PreparedAccuracyImage
    func extract(
        preparedImage: PreparedAccuracyImage,
        lines: [RecognizedTextLine],
        capturedAt: Date,
        sourceFileName: String
    ) async throws -> CloudExtractionResult
}

extension OptimizedCloudEventExtracting {
    func extract(
        image: ValidatedImage,
        lines: [RecognizedTextLine],
        capturedAt: Date,
        sourceFileName: String
    ) async throws -> CloudExtractionResult {
        let prepared = try await prepare(image: image)
        return try await extract(
            preparedImage: prepared,
            lines: lines,
            capturedAt: capturedAt,
            sourceFileName: sourceFileName
        )
    }
}

struct AccuracyImagePreprocessor: Sendable {
    static let longestEdge = 2_048
    static let maximumBytes = 4 * 1_024 * 1_024

    func prepare(_ image: CGImage) async throws -> PreparedAccuracyImage {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    continuation.resume(returning: try prepareSynchronously(image))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func prepareSynchronously(_ source: CGImage) throws -> PreparedAccuracyImage {
        var image = try scaled(source, maximumEdge: Self.longestEdge)
        let qualities: [Double] = [0.82, 0.72, 0.60, 0.48]

        for attempt in 0..<4 {
            for quality in qualities {
                let data = try jpeg(image, quality: quality)
                if data.count <= Self.maximumBytes {
                    return PreparedAccuracyImage(
                        jpegData: data,
                        pixelWidth: image.width,
                        pixelHeight: image.height
                    )
                }
            }
            guard attempt < 3 else { break }
            image = try scaled(image, maximumEdge: max(640, Int(Double(max(image.width, image.height)) * 0.78)))
        }
        throw CloudExtractionError.imageEncodingFailed
    }

    private func scaled(_ image: CGImage, maximumEdge: Int) throws -> CGImage {
        let currentEdge = max(image.width, image.height)
        guard currentEdge > maximumEdge else { return image }
        let ratio = Double(maximumEdge) / Double(currentEdge)
        let width = max(1, Int((Double(image.width) * ratio).rounded()))
        let height = max(1, Int((Double(image.height) * ratio).rounded()))
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            throw CloudExtractionError.imageEncodingFailed
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let output = context.makeImage() else {
            throw CloudExtractionError.imageEncodingFailed
        }
        return output
    }

    private func jpeg(_ image: CGImage, quality: Double) throws -> Data {
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
            [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination), data.length > 0 else {
            throw CloudExtractionError.imageEncodingFailed
        }
        return data as Data
    }
}

