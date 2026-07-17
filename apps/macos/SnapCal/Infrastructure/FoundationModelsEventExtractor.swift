import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

enum LocalSemanticEventExtractorFactory {
    static func live(
        calendar: Calendar = .current
    ) -> any LocalSemanticEventExtracting {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return FoundationModelsEventExtractor(calendar: calendar)
        }
        return DisabledLocalSemanticEventExtractor(
            reason: .operatingSystemUnsupported
        )
        #else
        return DisabledLocalSemanticEventExtractor(
            reason: .frameworkUnavailable
        )
        #endif
    }
}

#if canImport(FoundationModels)
@available(macOS 26.0, *)
@Generable
private struct GeneratedSemanticBatch {
    var hasEvents: Bool

    @Guide(
        description: "Zero to ten distinct calendar events in source order.",
        .maximumCount(10)
    )
    var events: [GeneratedSemanticEvent]
}

@available(macOS 26.0, *)
@Generable
private struct GeneratedSemanticEvent {
    @Guide(
        description: "Zero-based OCR line indexes belonging to this event.",
        .maximumCount(30)
    )
    var eventLineIndexes: [Int]

    var title: GeneratedTextField?
    var startDate: GeneratedDateField
    var startTime: GeneratedClockField?
    var endDate: GeneratedDateField?
    var endTime: GeneratedClockField?
    var location: GeneratedTextField?
}

@available(macOS 26.0, *)
@Generable
private struct GeneratedTextField {
    var value: String

    @Guide(description: "Supporting OCR line indexes.", .maximumCount(4))
    var evidenceLineIndexes: [Int]
}

@available(macOS 26.0, *)
@Generable
private struct GeneratedDateField {
    var year: Int?

    @Guide(description: "Calendar month.", .range(1...12))
    var month: Int

    @Guide(description: "Calendar day.", .range(1...31))
    var day: Int

    @Guide(description: "Supporting OCR line indexes.", .maximumCount(4))
    var evidenceLineIndexes: [Int]
}

@available(macOS 26.0, *)
@Generable
private struct GeneratedClockField {
    @Guide(description: "Hour in 24-hour time.", .range(0...23))
    var hour: Int

    @Guide(description: "Minute.", .range(0...59))
    var minute: Int

    @Guide(description: "Supporting OCR line indexes.", .maximumCount(4))
    var evidenceLineIndexes: [Int]
}

@available(macOS 26.0, *)
struct FoundationModelsEventExtractor: LocalSemanticEventExtracting {
    private static let modelName = "Apple Foundation Models"
    private static let maximumPromptLines = 150
    private static let maximumPromptCharacters = 20_000

    private let calendar: Calendar
    private let deterministicExtractor: LocalEventExtractor

    init(calendar: Calendar = .current) {
        self.calendar = calendar
        deterministicExtractor = LocalEventExtractor(calendar: calendar)
    }

    func extract(
        lines: [RecognizedTextLine],
        capturedAt: Date,
        sourceFileName: String
    ) async throws -> LocalSemanticExtractionResult {
        let boundedLines = bounded(lines)
        guard !boundedLines.isEmpty else {
            throw LocalSemanticExtractionError.noEventDetected
        }

        let model = SystemLanguageModel.default
        try validateAvailability(of: model, for: boundedLines)

        let session = LanguageModelSession(
            model: model,
            instructions: """
            Extract calendar events only from the numbered OCR lines. Never invent a date,
            clock time, location, title, or evidence index. Preserve Vietnamese diacritics,
            mixed Vietnamese-English text, event source order, and separate events only
            when each has independent date evidence. Words such as toi, tối, evening, or
            night are not clock times. Use zero-based indexes exactly as shown.
            """
        )

        let generated: GeneratedSemanticBatch
        do {
            let response = try await session.respond(
                to: prompt(for: boundedLines),
                generating: GeneratedSemanticBatch.self,
                includeSchemaInPrompt: true,
                options: GenerationOptions(
                    sampling: .greedy,
                    maximumResponseTokens: 2_048
                )
            )
            generated = response.content
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as LanguageModelSession.GenerationError {
            throw mapped(error)
        } catch {
            throw LocalSemanticExtractionError.invalidOutput
        }

        let drafts = try validate(
            generated,
            against: boundedLines,
            fullOCRLines: lines,
            capturedAt: capturedAt,
            sourceFileName: sourceFileName
        )
        return LocalSemanticExtractionResult(
            drafts: drafts,
            model: Self.modelName
        )
    }

    private func validateAvailability(
        of model: SystemLanguageModel,
        for lines: [RecognizedTextLine]
    ) throws {
        switch model.availability {
        case .available:
            break
        case .unavailable(let reason):
            let mappedReason: LocalSemanticUnavailableReason
            switch reason {
            case .deviceNotEligible:
                mappedReason = .deviceNotEligible
            case .appleIntelligenceNotEnabled:
                mappedReason = .appleIntelligenceNotEnabled
            case .modelNotReady:
                mappedReason = .modelNotReady
            @unknown default:
                mappedReason = .modelNotReady
            }
            throw LocalSemanticExtractionError.unavailable(mappedReason)
        }

        let locale = detectedLocale(in: lines)
        guard model.supportsLocale(locale) else {
            throw LocalSemanticExtractionError.unavailable(.unsupportedLocale)
        }
    }

    private func validate(
        _ batch: GeneratedSemanticBatch,
        against lines: [RecognizedTextLine],
        fullOCRLines: [RecognizedTextLine],
        capturedAt: Date,
        sourceFileName: String
    ) throws -> [EventDraft] {
        guard batch.hasEvents else {
            guard batch.events.isEmpty else {
                throw LocalSemanticExtractionError.invalidOutput
            }
            throw LocalSemanticExtractionError.noEventDetected
        }
        guard !batch.events.isEmpty, batch.events.count <= 10 else {
            throw LocalSemanticExtractionError.invalidOutput
        }

        let orderedEvents = batch.events.sorted {
            ($0.eventLineIndexes.min() ?? Int.max) < ($1.eventLineIndexes.min() ?? Int.max)
        }
        var dateEvidenceSets = Set<String>()
        var drafts: [EventDraft] = []

        for event in orderedEvents {
            let eventIndexes = try validatedIndexes(
                event.eventLineIndexes,
                upperBound: lines.count,
                allowEmpty: false
            )
            let eventIndexSet = Set(eventIndexes)
            let dateIndexes = try validatedFieldIndexes(
                event.startDate.evidenceLineIndexes,
                eventIndexes: eventIndexSet,
                upperBound: lines.count,
                allowEmpty: false
            )
            let dateEvidenceKey = dateIndexes.map(String.init).joined(separator: ",")
            guard dateEvidenceSets.insert(dateEvidenceKey).inserted else {
                throw LocalSemanticExtractionError.invalidOutput
            }

            let timeIndexes = try event.startTime.map {
                try validatedFieldIndexes(
                    $0.evidenceLineIndexes,
                    eventIndexes: eventIndexSet,
                    upperBound: lines.count,
                    allowEmpty: false
                )
            } ?? []
            let titleIndexes = try event.title.map {
                try validatedFieldIndexes(
                    $0.evidenceLineIndexes,
                    eventIndexes: eventIndexSet,
                    upperBound: lines.count,
                    allowEmpty: false
                )
            } ?? []
            let locationIndexes = try event.location.map {
                try validatedFieldIndexes(
                    $0.evidenceLineIndexes,
                    eventIndexes: eventIndexSet,
                    upperBound: lines.count,
                    allowEmpty: false
                )
            } ?? []

            let eventLines = eventIndexes.map { lines[$0] }
            let temporalLines = orderedUnique(dateIndexes + timeIndexes).map { lines[$0] }
            let corroborated = try deterministicExtractor.extract(
                lines: temporalLines,
                capturedAt: capturedAt,
                sourceFileName: sourceFileName
            )
            try validateStart(event, against: corroborated.start.value)

            let parsed = try deterministicExtractor.extract(
                lines: eventLines,
                capturedAt: capturedAt,
                sourceFileName: sourceFileName
            )
            guard let parsedStart = parsed.start.value,
                  sameMinute(parsedStart, corroborated.start.value) else {
                throw LocalSemanticExtractionError.invalidOutput
            }

            drafts.append(makeDraft(
                from: parsed,
                proposal: event,
                titleIndexes: titleIndexes,
                locationIndexes: locationIndexes,
                lines: lines,
                fullOCRLines: fullOCRLines
            ))
        }
        return drafts
    }

    private func makeDraft(
        from parsed: EventDraft,
        proposal: GeneratedSemanticEvent,
        titleIndexes: [Int],
        locationIndexes: [Int],
        lines: [RecognizedTextLine],
        fullOCRLines: [RecognizedTextLine]
    ) -> EventDraft {
        var title = parsed.title
        var location = parsed.location
        var ambiguities = parsed.ambiguities

        if let proposalTitle = proposal.title {
            title = validatedTextField(
                proposalTitle,
                indexes: titleIndexes,
                lines: lines,
                fallback: parsed.title,
                field: .title,
                ambiguities: &ambiguities
            )
        }
        if let proposalLocation = proposal.location {
            location = validatedTextField(
                proposalLocation,
                indexes: locationIndexes,
                lines: lines,
                fallback: parsed.location,
                field: .location,
                ambiguities: &ambiguities
            )
        }

        return EventDraft(
            id: parsed.id,
            createdAt: parsed.createdAt,
            capturedAt: parsed.capturedAt,
            sourceFileName: parsed.sourceFileName,
            sourceFingerprint: parsed.sourceFingerprint,
            detectedLanguage: parsed.detectedLanguage,
            rawOCRText: fullOCRLines.map(\.text).joined(separator: "\n"),
            title: title,
            start: parsed.start,
            end: parsed.end,
            location: location,
            description: parsed.description,
            reminders: parsed.reminders,
            isAllDay: parsed.isAllDay,
            ambiguities: ambiguities,
            requiresUserConfirmation: parsed.requiresUserConfirmation
        )
    }

    private func validatedTextField(
        _ proposal: GeneratedTextField,
        indexes: [Int],
        lines: [RecognizedTextLine],
        fallback: ExtractedField<String>,
        field: AmbiguityField,
        ambiguities: inout [DraftAmbiguity]
    ) -> ExtractedField<String> {
        let evidenceLines = indexes.map { lines[$0] }
        let evidenceText = evidenceLines.map(\.text).joined(separator: " • ")
        let value = proposal.value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty,
              hasTokenOverlap(value, evidenceText) else {
            ambiguities.append(DraftAmbiguity(
                field: field,
                message: "The on-device semantic proposal was not supported by its OCR evidence, so SnapCal kept the deterministic value.",
                severity: .medium
            ))
            return fallback
        }
        let confidence = min(
            evidenceLines.map(\.confidence).min() ?? 0,
            normalized(value) == normalized(evidenceText) ? 0.92 : 0.84
        )
        return ExtractedField(
            value: value,
            evidenceText: evidenceText,
            confidence: confidence
        )
    }

    private func validateStart(
        _ event: GeneratedSemanticEvent,
        against start: Date?
    ) throws {
        guard let start else {
            throw LocalSemanticExtractionError.invalidOutput
        }
        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: start
        )
        guard components.month == event.startDate.month,
              components.day == event.startDate.day else {
            throw LocalSemanticExtractionError.invalidOutput
        }
        if let year = event.startDate.year,
           components.year != normalizedYear(year) {
            throw LocalSemanticExtractionError.invalidOutput
        }
        if let time = event.startTime,
           (components.hour != time.hour || components.minute != time.minute) {
            throw LocalSemanticExtractionError.invalidOutput
        }
    }

    private func validatedFieldIndexes(
        _ indexes: [Int],
        eventIndexes: Set<Int>,
        upperBound: Int,
        allowEmpty: Bool
    ) throws -> [Int] {
        let result = try validatedIndexes(
            indexes,
            upperBound: upperBound,
            allowEmpty: allowEmpty
        )
        guard result.allSatisfy(eventIndexes.contains) else {
            throw LocalSemanticExtractionError.invalidOutput
        }
        return result
    }

    private func validatedIndexes(
        _ indexes: [Int],
        upperBound: Int,
        allowEmpty: Bool
    ) throws -> [Int] {
        let result = orderedUnique(indexes).sorted()
        guard (allowEmpty || !result.isEmpty),
              result.allSatisfy({ $0 >= 0 && $0 < upperBound }) else {
            throw LocalSemanticExtractionError.invalidOutput
        }
        return result
    }

    private func orderedUnique(_ values: [Int]) -> [Int] {
        var seen = Set<Int>()
        return values.filter { seen.insert($0).inserted }
    }

    private func sameMinute(_ left: Date, _ right: Date?) -> Bool {
        guard let right else { return false }
        return calendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: left
        ) == calendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: right
        )
    }

    private func normalizedYear(_ year: Int) -> Int {
        year < 100 ? 2_000 + year : year
    }

    private func hasTokenOverlap(_ value: String, _ evidence: String) -> Bool {
        let valueTokens = Set(tokens(in: value))
        let evidenceTokens = Set(tokens(in: evidence))
        guard !valueTokens.isEmpty else { return false }
        let overlap = valueTokens.intersection(evidenceTokens).count
        return Double(overlap) / Double(valueTokens.count) >= 0.4
    }

    private func tokens(in value: String) -> [String] {
        normalized(value)
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { $0.count >= 2 }
    }

    private func normalized(_ value: String) -> String {
        value.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "vi_VN")
        ).lowercased()
    }

    private func bounded(_ lines: [RecognizedTextLine]) -> [RecognizedTextLine] {
        var result: [RecognizedTextLine] = []
        var characterCount = 0
        for line in lines.prefix(Self.maximumPromptLines) {
            let nextCount = characterCount + line.text.count
            guard nextCount <= Self.maximumPromptCharacters else { break }
            result.append(line)
            characterCount = nextCount
        }
        return result
    }

    private func prompt(for lines: [RecognizedTextLine]) -> String {
        let numbered = lines.enumerated().map { index, line in
            "[\(index)] \(line.text)"
        }.joined(separator: "\n")
        return """
        Extract zero to ten calendar events from these OCR lines. Each event must have
        independent date evidence. Return only indexes that appear below.

        \(numbered)
        """
    }

    private func detectedLocale(in lines: [RecognizedTextLine]) -> Locale {
        let text = lines.map(\.text).joined(separator: " ")
        let vietnameseScalars = "ăâđêôơưáàảãạấầẩẫậắằẳẵặéèẻẽẹếềểễệíìỉĩịóòỏõọốồổỗộớờởỡợúùủũụứừửữựýỳỷỹỵ"
        let folded = text.lowercased()
        return folded.contains(where: { vietnameseScalars.contains($0) })
            ? Locale(identifier: "vi_VN")
            : Locale(identifier: "en_US")
    }

    private func mapped(
        _ error: LanguageModelSession.GenerationError
    ) -> LocalSemanticExtractionError {
        switch error {
        case .exceededContextWindowSize:
            return .contextTooLarge
        case .assetsUnavailable:
            return .unavailable(.modelNotReady)
        case .guardrailViolation, .refusal:
            return .refused
        case .unsupportedLanguageOrLocale:
            return .unavailable(.unsupportedLocale)
        case .rateLimited, .concurrentRequests:
            return .rateLimited
        case .unsupportedGuide, .decodingFailure:
            return .invalidOutput
        @unknown default:
            return .invalidOutput
        }
    }
}
#endif
