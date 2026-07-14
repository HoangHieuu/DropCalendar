#!/usr/bin/env swift

import AppKit
import CryptoKit
import Foundation

private struct ExpectedEvent: Encodable {
    let title: String
    let start: String
    let end: String?
    let isAllDay: Bool
    let location: String?

    enum CodingKeys: String, CodingKey {
        case title, start, end, location
        case isAllDay = "is_all_day"
    }
}

private struct Provenance: Encodable {
    let kind: String
    let source: String
    let rightsHolder: String
    let licenseOrPermission: String
    let redistributable: Bool

    enum CodingKeys: String, CodingKey {
        case kind, source, redistributable
        case rightsHolder = "rights_holder"
        case licenseOrPermission = "license_or_permission"
    }
}

private struct ManifestItem: Encodable {
    let schemaVersion: Int
    let id: String
    let image: String
    let imageSHA256: String
    let language: String
    let sourceCategory: String
    let difficulties: [String]
    let capturedAt: String
    let timezone: String
    let expected: ExpectedEvent
    let provenance: Provenance
    let sanitized: Bool
    let synthetic: Bool

    enum CodingKeys: String, CodingKey {
        case id, image, language, difficulties, timezone, expected, provenance, sanitized, synthetic
        case schemaVersion = "schema_version"
        case imageSHA256 = "image_sha256"
        case sourceCategory = "source_category"
        case capturedAt = "captured_at"
    }
}

private struct FixtureDefinition {
    let id: String
    let language: String
    let sourceCategory: String
    let difficulties: [String]
    let title: String
    let scheduleLines: [String]
    let start: String
    let end: String
    let location: String
    let width: Int
    let height: Int
}

private let sourceCategories = [
    "facebook", "tiktok", "instagram", "website", "university",
    "workshop", "hackathon", "concert", "webinar", "online_event",
]

private let backgrounds: [(NSColor, NSColor)] = [
    (NSColor(calibratedRed: 0.07, green: 0.09, blue: 0.18, alpha: 1), NSColor(calibratedRed: 0.35, green: 0.80, blue: 0.96, alpha: 1)),
    (NSColor(calibratedRed: 0.15, green: 0.05, blue: 0.19, alpha: 1), NSColor(calibratedRed: 0.94, green: 0.46, blue: 0.72, alpha: 1)),
    (NSColor(calibratedRed: 0.04, green: 0.18, blue: 0.14, alpha: 1), NSColor(calibratedRed: 0.55, green: 0.95, blue: 0.62, alpha: 1)),
    (NSColor(calibratedRed: 0.19, green: 0.10, blue: 0.03, alpha: 1), NSColor(calibratedRed: 1.00, green: 0.72, blue: 0.30, alpha: 1)),
]

private func fixture(index: Int) -> FixtureDefinition {
    let language: String
    if index <= 50 {
        language = "vietnamese"
    } else if index <= 80 {
        language = "english"
    } else {
        language = "mixed"
    }

    let month = 8 + ((index - 1) % 3)
    let day = 10 + ((index - 1) % 18)
    let hour = 18 + ((index - 1) % 3)
    let minute = index.isMultiple(of: 2) ? 30 : 0
    let sourceCategory = sourceCategories[(index - 1) % sourceCategories.count]
    var difficulties: [String] = []
    if index.isMultiple(of: 4) { difficulties.append("noisy") }
    if index.isMultiple(of: 5) { difficulties.append("decorative_font") }
    if index.isMultiple(of: 7) { difficulties.append("low_resolution") }
    if index.isMultiple(of: 9) { difficulties.append("dense_layout") }
    if language == "mixed" { difficulties.append("mixed_language") }
    if difficulties.isEmpty { difficulties.append("clean") }

    let title: String
    var scheduleLines: [String]
    let location: String
    switch language {
    case "vietnamese":
        title = String(format: "HỘI THẢO CÔNG NGHỆ %03d", index)
        scheduleLines = [String(format: "%02dh%02d ngày %d/%d/2026", hour, minute, day, month)]
        location = index.isMultiple(of: 3)
            ? "Online - Zoom"
            : "Đại học Bách Khoa TP.HCM"
    case "english":
        title = String(format: "AI COMMUNITY MEETUP %03d", index)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMMM"
        var components = DateComponents()
        components.year = 2026
        components.month = month
        components.day = day
        let monthName = formatter.string(from: Calendar(identifier: .gregorian).date(from: components)!)
        let displayHour = hour > 12 ? hour - 12 : hour
        scheduleLines = [String(format: "%@ %d, 2026 at %d:%02d PM", monthName, day, displayHour, minute)]
        location = index.isMultiple(of: 3)
            ? "Online - Google Meet"
            : "Dreamplex, District 1, Ho Chi Minh City"
    default:
        title = String(format: "WORKSHOP CÔNG NGHỆ %03d", index)
        scheduleLines = [String(format: "%02dh%02d ngày %d/%d/2026", hour, minute, day, month)]
        location = index.isMultiple(of: 3)
            ? "Online - Zoom"
            : "University Campus, Ho Chi Minh City"
    }

    var expectedMonth = month
    var expectedDay = day
    var expectedHour = hour
    var expectedMinute = minute
    switch index {
    case 1...5:
        scheduleLines = ["Ngày mai lúc 20h"]
        expectedMonth = 7
        expectedDay = 15
        expectedHour = 20
        expectedMinute = 0
    case 6...10:
        scheduleLines = ["T7 lúc 20h"]
        expectedMonth = 7
        expectedDay = 18
        expectedHour = 20
        expectedMinute = 0
    case 11...15:
        scheduleLines = [
            "Đăng ký trước 15/8/2026",
            "Sự kiện bắt đầu 20h ngày 20/8/2026",
        ]
        expectedMonth = 8
        expectedDay = 20
        expectedHour = 20
        expectedMinute = 0
    case 51...55:
        scheduleLines = ["Tomorrow at 8 PM"]
        expectedMonth = 7
        expectedDay = 15
        expectedHour = 20
        expectedMinute = 0
    case 56...60:
        scheduleLines = [
            "August 16, 2026",
            "Doors open at 6 PM, show starts at 7 PM",
        ]
        expectedMonth = 8
        expectedDay = 16
        expectedHour = 19
        expectedMinute = 0
    case 61...65:
        scheduleLines = [
            "Registration deadline August 15, 2026",
            "Event starts August 20, 2026 at 7 PM",
        ]
        expectedMonth = 8
        expectedDay = 20
        expectedHour = 19
        expectedMinute = 0
    case 81...85:
        scheduleLines = ["Tomorrow • Ngày mai lúc 20h"]
        expectedMonth = 7
        expectedDay = 15
        expectedHour = 20
        expectedMinute = 0
    case 86...90:
        scheduleLines = ["20:OO ngày 15/8/2026"]
        expectedMonth = 8
        expectedDay = 15
        expectedHour = 20
        expectedMinute = 0
    case 91...95:
        scheduleLines = [
            "Doors open at 6 PM",
            "Sự kiện bắt đầu lúc 19h ngày 16/8/2026",
        ]
        expectedMonth = 8
        expectedDay = 16
        expectedHour = 19
        expectedMinute = 0
    case 96...100:
        scheduleLines = [
            "Đăng ký trước 15/8/2026",
            "Event starts 20/8/2026 at 7 PM",
        ]
        expectedMonth = 8
        expectedDay = 20
        expectedHour = 19
        expectedMinute = 0
    default:
        break
    }

    let start = String(
        format: "2026-%02d-%02dT%02d:%02d:00+07:00",
        expectedMonth,
        expectedDay,
        expectedHour,
        expectedMinute
    )
    let endHour = min(expectedHour + 2, 23)
    let end = String(
        format: "2026-%02d-%02dT%02d:%02d:00+07:00",
        expectedMonth,
        expectedDay,
        endHour,
        expectedMinute
    )
    let lowResolution = difficulties.contains("low_resolution")
    return FixtureDefinition(
        id: String(format: "%@-%03d", language == "vietnamese" ? "vi" : language == "english" ? "en" : "mixed", index),
        language: language,
        sourceCategory: sourceCategory,
        difficulties: difficulties,
        title: title,
        scheduleLines: scheduleLines,
        start: start,
        end: end,
        location: location,
        width: lowResolution ? 600 : 1200,
        height: lowResolution ? 450 : 900
    )
}

private func draw(_ definition: FixtureDefinition, index: Int) throws -> Data {
    guard let representation = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: definition.width,
        pixelsHigh: definition.height,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bitmapFormat: [],
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: representation) else {
        throw NSError(domain: "SnapCalBenchmark", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to create bitmap context"])
    }

    let scale = CGFloat(definition.width) / 1200
    let palette = backgrounds[(index - 1) % backgrounds.count]
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    palette.0.setFill()
    NSRect(x: 0, y: 0, width: definition.width, height: definition.height).fill()

    palette.1.withAlphaComponent(0.18).setFill()
    NSBezierPath(ovalIn: NSRect(x: -180 * scale, y: 560 * scale, width: 620 * scale, height: 620 * scale)).fill()
    NSBezierPath(ovalIn: NSRect(x: 850 * scale, y: -170 * scale, width: 520 * scale, height: 520 * scale)).fill()

    if definition.difficulties.contains("noisy") {
        palette.1.withAlphaComponent(0.16).setStroke()
        for offset in stride(from: 0, through: definition.width, by: max(12, definition.width / 36)) {
            let path = NSBezierPath()
            path.move(to: NSPoint(x: offset, y: 0))
            path.line(to: NSPoint(x: min(definition.width, offset + definition.height / 2), y: definition.height))
            path.lineWidth = max(1, 2 * scale)
            path.stroke()
        }
    }

    drawText(
        definition.sourceCategory.replacingOccurrences(of: "_", with: " ").uppercased(),
        rect: NSRect(x: 92 * scale, y: 785 * scale, width: 1016 * scale, height: 54 * scale),
        font: NSFont.monospacedSystemFont(ofSize: 24 * scale, weight: .semibold),
        color: palette.1
    )

    let titleFontName = definition.difficulties.contains("decorative_font") ? "Didot-Bold" : "HelveticaNeue-Bold"
    let titleFont = NSFont(name: titleFontName, size: 72 * scale)
        ?? NSFont.systemFont(ofSize: 72 * scale, weight: .bold)
    drawText(
        definition.title,
        rect: NSRect(x: 92 * scale, y: 535 * scale, width: 1016 * scale, height: 210 * scale),
        font: titleFont,
        color: .white
    )

    for (lineIndex, scheduleLine) in definition.scheduleLines.enumerated() {
        drawText(
            scheduleLine,
            rect: NSRect(
                x: 92 * scale,
                y: (410 - CGFloat(lineIndex) * 72) * scale,
                width: 1016 * scale,
                height: 66 * scale
            ),
            font: NSFont.systemFont(ofSize: 38 * scale, weight: .semibold),
            color: palette.1
        )
    }
    drawText(
        definition.location,
        rect: NSRect(x: 92 * scale, y: 245 * scale, width: 1016 * scale, height: 72 * scale),
        font: NSFont.systemFont(ofSize: 34 * scale, weight: .medium),
        color: .white
    )
    drawText(
        definition.language == "english" ? "Register now • Free entry" : "Đăng ký ngay • Vào cửa miễn phí",
        rect: NSRect(x: 92 * scale, y: 125 * scale, width: 1016 * scale, height: 58 * scale),
        font: NSFont.systemFont(ofSize: 27 * scale, weight: .regular),
        color: NSColor.white.withAlphaComponent(0.78)
    )
    NSGraphicsContext.restoreGraphicsState()

    guard let data = representation.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "SnapCalBenchmark", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unable to encode PNG"])
    }
    return data
}

private func drawText(_ text: String, rect: NSRect, font: NSFont, color: NSColor) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineBreakMode = .byWordWrapping
    paragraph.alignment = .left
    (text as NSString).draw(
        with: rect,
        options: [.usesLineFragmentOrigin, .usesFontLeading],
        attributes: [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph,
        ]
    )
}

private func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

private let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
private let packageRoot = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
private let corpusRoot = packageRoot.appendingPathComponent("corpus", isDirectory: true)
private let imageRoot = corpusRoot.appendingPathComponent("images", isDirectory: true)
private let manifestURL = corpusRoot.appendingPathComponent("manifest.jsonl")
private let fileManager = FileManager.default

try? fileManager.removeItem(at: imageRoot)
try fileManager.createDirectory(at: imageRoot, withIntermediateDirectories: true)

let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
var manifest = Data()

for index in 1...100 {
    let definition = fixture(index: index)
    let png = try draw(definition, index: index)
    let fileName = definition.id + ".png"
    try png.write(to: imageRoot.appendingPathComponent(fileName), options: .atomic)
    let item = ManifestItem(
        schemaVersion: 1,
        id: definition.id,
        image: "images/\(fileName)",
        imageSHA256: sha256(png),
        language: definition.language,
        sourceCategory: definition.sourceCategory,
        difficulties: definition.difficulties,
        capturedAt: "2026-07-14T09:00:00+07:00",
        timezone: "Asia/Ho_Chi_Minh",
        expected: ExpectedEvent(
            title: definition.title,
            start: definition.start,
            end: definition.end,
            isAllDay: false,
            location: definition.location
        ),
        provenance: Provenance(
            kind: "generated",
            source: "packages/benchmark/tools/GenerateSyntheticCorpus.swift",
            rightsHolder: "SnapCal contributors",
            licenseOrPermission: "Project-generated redistributable benchmark fixture",
            redistributable: true
        ),
        sanitized: true,
        synthetic: true
    )
    manifest.append(try encoder.encode(item))
    manifest.append(0x0A)
}

try manifest.write(to: manifestURL, options: .atomic)
print("Generated 100 synthetic benchmark images and \(manifestURL.path)")
