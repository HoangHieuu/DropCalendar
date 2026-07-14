import CoreGraphics
import CryptoKit
import Foundation
import ImageIO

struct ValidatedImage {
    let cgImage: CGImage
    let fileName: String
    let capturedAt: Date
    let originalData: Data?
    let sourceFingerprint: String?

    init(
        cgImage: CGImage,
        fileName: String,
        capturedAt: Date,
        originalData: Data? = nil,
        sourceFingerprint: String? = nil
    ) {
        self.cgImage = cgImage
        self.fileName = fileName
        self.capturedAt = capturedAt
        self.originalData = originalData
        self.sourceFingerprint = sourceFingerprint
    }
}

protocol ImageValidating {
    func validate(_ url: URL) throws -> ValidatedImage
    func validate(_ clipboardImage: ClipboardImage) throws -> ValidatedImage
}

enum ImageValidationError: LocalizedError, Equatable {
    case unsupportedFormat
    case emptyFile
    case fileTooLarge
    case corruptImage
    case unreadableFile

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            return "Choose a PNG, JPG, JPEG, or HEIC image."
        case .emptyFile:
            return "The selected image is empty."
        case .fileTooLarge:
            return "The image is larger than 20 MB. Choose a smaller screenshot."
        case .corruptImage:
            return "The image cannot be decoded or appears to be corrupted."
        case .unreadableFile:
            return "SnapCal could not read the selected file."
        }
    }
}

struct ImageValidator: ImageValidating {
    static let maximumBytes = 20 * 1_024 * 1_024
    private let allowedExtensions = Set(["png", "jpg", "jpeg", "heic"])

    func validate(_ url: URL) throws -> ValidatedImage {
        guard allowedExtensions.contains(url.pathExtension.lowercased()) else {
            throw ImageValidationError.unsupportedFormat
        }

        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let data: Data
        do {
            data = try Data(contentsOf: url, options: .mappedIfSafe)
        } catch {
            throw ImageValidationError.unreadableFile
        }

        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        return try validate(
            data: data,
            fileName: url.lastPathComponent,
            capturedAt: values?.contentModificationDate ?? Date()
        )
    }

    func validate(_ clipboardImage: ClipboardImage) throws -> ValidatedImage {
        guard allowedExtensions.contains(
            URL(fileURLWithPath: clipboardImage.fileName).pathExtension.lowercased()
        ) else {
            throw ImageValidationError.unsupportedFormat
        }
        return try validate(
            data: clipboardImage.data,
            fileName: clipboardImage.fileName,
            capturedAt: clipboardImage.capturedAt
        )
    }

    private func validate(
        data: Data,
        fileName: String,
        capturedAt: Date
    ) throws -> ValidatedImage {
        guard !data.isEmpty else {
            throw ImageValidationError.emptyFile
        }
        guard data.count <= Self.maximumBytes else {
            throw ImageValidationError.fileTooLarge
        }
        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            CGImageSourceGetCount(source) > 0,
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw ImageValidationError.corruptImage
        }

        return ValidatedImage(
            cgImage: image,
            fileName: fileName,
            capturedAt: capturedAt,
            originalData: data,
            sourceFingerprint: SHA256.hash(data: data)
                .map { String(format: "%02x", $0) }
                .joined()
        )
    }
}
