import CoreGraphics
import Foundation
import ImageIO

struct ValidatedImage {
    let cgImage: CGImage
    let fileName: String
    let capturedAt: Date
}

protocol ImageValidating {
    func validate(_ url: URL) throws -> ValidatedImage
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

        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        return ValidatedImage(
            cgImage: image,
            fileName: url.lastPathComponent,
            capturedAt: values?.contentModificationDate ?? Date()
        )
    }
}
