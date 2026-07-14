import Foundation

struct EventReminder: Identifiable, Codable, Equatable, Hashable, Sendable {
    enum Method: String, CaseIterable, Codable, Sendable {
        case popup
        case email
    }

    var id: String { "\(method.rawValue)-\(minutesBefore)" }
    var method: Method
    var minutesBefore: Int

    init(method: Method = .popup, minutesBefore: Int) {
        self.method = method
        self.minutesBefore = minutesBefore
    }
}

enum ReminderPolicy {
    static let maximumOverrides = 5
    static let maximumMinutesBefore = 40_320

    static func suggestions(for draft: EventDraft, now: Date = Date()) -> [EventReminder] {
        guard let start = draft.start.value, start > now else { return [] }

        let minutes: [Int]
        if draft.isAllDay {
            // An all-day event starts at midnight. 900 minutes before is 9 AM
            // on the previous day in the event timezone.
            minutes = [900]
        } else if LocationNormalizer.isOnline(draft.location.value) {
            minutes = [30, 5]
        } else if isWorkshopOrSeminar(draft) && start.timeIntervalSince(now) > 86_400 {
            minutes = [1_440, 120]
        } else if start.timeIntervalSince(now) > 86_400 {
            minutes = [1_440, 60]
        } else {
            minutes = [60, 15]
        }

        return minutes
            .filter { start.addingTimeInterval(-Double($0 * 60)) > now }
            .map { EventReminder(minutesBefore: $0) }
    }

    static func validate(_ reminders: [EventReminder]) throws {
        guard reminders.count <= maximumOverrides else {
            throw ReminderValidationError.tooMany
        }
        guard reminders.allSatisfy({
            (0...maximumMinutesBefore).contains($0.minutesBefore)
        }) else {
            throw ReminderValidationError.outOfRange
        }
        guard Set(reminders.map(\.id)).count == reminders.count else {
            throw ReminderValidationError.duplicate
        }
    }

    static func label(for minutes: Int, allDay: Bool = false) -> String {
        if allDay && minutes == 900 { return "1 day before at 9:00 AM" }
        if minutes == 0 { return "At event time" }
        if minutes % 1_440 == 0 {
            let days = minutes / 1_440
            return "\(days) day\(days == 1 ? "" : "s") before"
        }
        if minutes % 60 == 0 {
            let hours = minutes / 60
            return "\(hours) hour\(hours == 1 ? "" : "s") before"
        }
        return "\(minutes) minutes before"
    }

    private static func isWorkshopOrSeminar(_ draft: EventDraft) -> Bool {
        let text = [draft.title.value, draft.description.value]
            .compactMap { $0 }
            .joined(separator: " ")
            .folding(
                options: [.diacriticInsensitive, .caseInsensitive],
                locale: Locale(identifier: "vi_VN")
            )
            .lowercased()
        return ["workshop", "seminar", "hoi thao", "tap huan"].contains {
            text.contains($0)
        }
    }
}

enum ReminderValidationError: Error, Equatable {
    case tooMany
    case outOfRange
    case duplicate
}

struct DuplicateSignature: Equatable, Sendable {
    let id: UUID
    let sourceFingerprint: String?
    let title: String?
    let start: Date?
    let location: String?
}

struct DuplicateWarning: Identifiable, Equatable, Sendable {
    enum Kind: String, Sendable {
        case sameScreenshot
        case sameTitleAndTime
        case sameTitleDateAndLocation
    }

    enum Severity: String, Sendable {
        case high
        case soft
    }

    let id: String
    let matchedDraftID: UUID
    let kind: Kind
    let severity: Severity

    var message: String {
        switch kind {
        case .sameScreenshot:
            return "This screenshot was already imported into a recent SnapCal draft."
        case .sameTitleAndTime:
            return "A recent SnapCal draft has the same title and start time."
        case .sameTitleDateAndLocation:
            return "A recent draft has the same title, date, and location. Review before creating another event."
        }
    }
}

enum DuplicateDetector {
    static func warnings(
        for candidate: DuplicateSignature,
        among history: [DuplicateSignature],
        calendar: Calendar = .current
    ) -> [DuplicateWarning] {
        let candidateTitle = normalized(candidate.title)
        let candidateLocation = normalized(candidate.location)

        return history.compactMap { existing in
            guard existing.id != candidate.id else { return nil }
            if let fingerprint = candidate.sourceFingerprint,
               !fingerprint.isEmpty,
               fingerprint == existing.sourceFingerprint {
                return warning(.sameScreenshot, .high, existing.id)
            }

            let existingTitle = normalized(existing.title)
            guard !candidateTitle.isEmpty, candidateTitle == existingTitle else {
                return nil
            }
            if let start = candidate.start,
               let existingStart = existing.start,
               abs(start.timeIntervalSince(existingStart)) <= 300 {
                return warning(.sameTitleAndTime, .high, existing.id)
            }

            let existingLocation = normalized(existing.location)
            if let start = candidate.start,
               let existingStart = existing.start,
               calendar.isDate(start, inSameDayAs: existingStart),
               !candidateLocation.isEmpty,
               candidateLocation == existingLocation {
                return warning(.sameTitleDateAndLocation, .soft, existing.id)
            }
            return nil
        }
        .sorted { lhs, rhs in
            if lhs.severity != rhs.severity { return lhs.severity == .high }
            return lhs.id < rhs.id
        }
    }

    private static func warning(
        _ kind: DuplicateWarning.Kind,
        _ severity: DuplicateWarning.Severity,
        _ draftID: UUID
    ) -> DuplicateWarning {
        DuplicateWarning(
            id: "\(kind.rawValue)-\(draftID.uuidString)",
            matchedDraftID: draftID,
            kind: kind,
            severity: severity
        )
    }

    private static func normalized(_ value: String?) -> String {
        (value ?? "")
            .folding(
                options: [.diacriticInsensitive, .caseInsensitive],
                locale: Locale(identifier: "vi_VN")
            )
            .lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .joined(separator: " ")
    }
}

enum LocationNormalizer {
    static func normalize(_ draft: inout EventDraft) {
        guard let rawLocation = draft.location.value?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !rawLocation.isEmpty else { return }

        if isHybrid(rawLocation) {
            draft.location.value = "Hybrid — \(rawLocation)"
            appendMeetingDetails(rawLocation, to: &draft)
        } else if isOnline(rawLocation) {
            draft.location.value = "Online"
            appendMeetingDetails(rawLocation, to: &draft)
        }
    }

    static func isOnline(_ value: String?) -> Bool {
        let normalized = normalized(value)
        return [
            "online", "truc tuyen", "zoom", "google meet", "microsoft teams",
            "livestream", "live stream", "tiktok live", "facebook live"
        ].contains { normalized.contains($0) }
    }

    private static func isHybrid(_ value: String) -> Bool {
        let text = normalized(value)
        return text.contains("hybrid")
            || text.contains("ket hop truc tiep")
            || (text.contains("truc tiep") && isOnline(value))
    }

    private static func appendMeetingDetails(_ rawLocation: String, to draft: inout EventDraft) {
        let existing = draft.description.value?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !existing.localizedCaseInsensitiveContains(rawLocation) else { return }
        let updated = existing.isEmpty
            ? "Meeting details: \(rawLocation)"
            : "\(existing)\n\nMeeting details: \(rawLocation)"
        draft.description.value = updated
        draft.description.confidence = max(draft.description.confidence, draft.location.confidence)
    }

    private static func normalized(_ value: String?) -> String {
        (value ?? "")
            .folding(
                options: [.diacriticInsensitive, .caseInsensitive],
                locale: Locale(identifier: "vi_VN")
            )
            .lowercased()
    }
}
