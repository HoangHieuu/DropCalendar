import AppKit
import Foundation

struct ClipboardImage: Sendable {
    let data: Data
    let fileName: String
    let capturedAt: Date
}

@MainActor
protocol ClipboardImageReading {
    func readImage() throws -> ClipboardImage
}

enum ClipboardImageReadingError: LocalizedError, Equatable {
    case noSupportedImage
    case unreadableImage

    var errorDescription: String? {
        switch self {
        case .noSupportedImage:
            return "Copy one PNG, JPEG, or HEIC image, then try again."
        case .unreadableImage:
            return "SnapCal could not read the copied image. Copy it again and retry."
        }
    }
}

@MainActor
struct SystemClipboardImageReader: ClipboardImageReading {
    static let jpegType = NSPasteboard.PasteboardType("public.jpeg")
    static let heicType = NSPasteboard.PasteboardType("public.heic")

    private let pasteboard: NSPasteboard
    private let now: () -> Date

    init(
        pasteboard: NSPasteboard = .general,
        now: @escaping () -> Date = Date.init
    ) {
        self.pasteboard = pasteboard
        self.now = now
    }

    func readImage() throws -> ClipboardImage {
        let preferredTypes: [NSPasteboard.PasteboardType] = [
            .png,
            Self.jpegType,
            Self.heicType,
            .tiff,
            .fileURL
        ]
        guard let type = pasteboard.availableType(from: preferredTypes) else {
            throw ClipboardImageReadingError.noSupportedImage
        }

        if type == .fileURL {
            return try readFileURL()
        }

        guard let data = pasteboard.data(forType: type) else {
            throw ClipboardImageReadingError.unreadableImage
        }
        if type == .tiff {
            return ClipboardImage(
                data: try convertTIFFToPNG(data),
                fileName: "Clipboard Screenshot.png",
                capturedAt: now()
            )
        }

        return ClipboardImage(
            data: data,
            fileName: "Clipboard Screenshot.\(fileExtension(for: type))",
            capturedAt: now()
        )
    }

    private func readFileURL() throws -> ClipboardImage {
        guard
            let value = pasteboard.string(forType: .fileURL),
            let url = URL(string: value),
            url.isFileURL
        else {
            throw ClipboardImageReadingError.unreadableImage
        }

        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }

        let data: Data
        do {
            data = try Data(contentsOf: url, options: .mappedIfSafe)
        } catch {
            throw ClipboardImageReadingError.unreadableImage
        }
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        return ClipboardImage(
            data: data,
            fileName: url.lastPathComponent,
            capturedAt: values?.contentModificationDate ?? now()
        )
    }

    private func convertTIFFToPNG(_ data: Data) throws -> Data {
        guard
            !data.isEmpty,
            let bitmap = NSBitmapImageRep(data: data),
            let pngData = bitmap.representation(using: .png, properties: [:])
        else {
            throw ClipboardImageReadingError.unreadableImage
        }
        return pngData
    }

    private func fileExtension(for type: NSPasteboard.PasteboardType) -> String {
        switch type {
        case .png: return "png"
        case Self.jpegType: return "jpg"
        case Self.heicType: return "heic"
        default: return "png"
        }
    }
}

@MainActor
struct DisabledClipboardImageReader: ClipboardImageReading {
    func readImage() throws -> ClipboardImage {
        throw ClipboardImageReadingError.noSupportedImage
    }
}
