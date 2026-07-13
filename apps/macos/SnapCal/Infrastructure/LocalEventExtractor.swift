import Foundation

protocol EventExtracting {
    func extract(
        lines: [RecognizedTextLine],
        capturedAt: Date,
        sourceFileName: String
    ) throws -> EventDraft
}

enum DraftExtractionError: LocalizedError, Equatable {
    case noEventDetected

    var errorDescription: String? {
        "No reliable date or time evidence was found. Try a clearer event screenshot."
    }
}

struct LocalEventExtractor: EventExtracting {
    private struct DateEvidence {
        let day: Int
        let month: Int
        let year: Int?
        let line: RecognizedTextLine
    }

    private struct TimeEvidence {
        let hour: Int
        let minute: Int
        let line: RecognizedTextLine
    }

    private struct DateRangeEvidence {
        let start: DateEvidence
        let end: DateEvidence
    }

    private var calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    func extract(
        lines: [RecognizedTextLine],
        capturedAt: Date,
        sourceFileName: String
    ) throws -> EventDraft {
        let cleanedLines = lines
            .map {
                RecognizedTextLine(
                    text: $0.text.trimmingCharacters(in: .whitespacesAndNewlines),
                    confidence: $0.confidence,
                    region: $0.region
                )
            }
            .filter { !$0.text.isEmpty }

        let explicitRange = cleanedLines.compactMap(parseDateRange).first
        let standaloneYear = cleanedLines.compactMap(parseStandaloneYear).first
        let dateCandidates = cleanedLines.compactMap(parseDate).map {
            DateEvidence(
                day: $0.day,
                month: $0.month,
                year: $0.year ?? standaloneYear,
                line: $0.line
            )
        }
        let dateEvidence = explicitRange?.start ?? dateCandidates.first
        let endDateEvidence = explicitRange?.end ?? dateCandidates.dropFirst().first
        let timeEvidence = cleanedLines.compactMap(parseTime).first
        guard dateEvidence != nil || timeEvidence != nil else {
            throw DraftExtractionError.noEventDetected
        }

        let locationLine = cleanedLines.first(where: isLikelyLocation)
        let titleLine = selectTitle(in: cleanedLines)

        let rawText = cleanedLines.map(\.text).joined(separator: "\n")
        let averageConfidence = cleanedLines.isEmpty
            ? 0
            : cleanedLines.map(\.confidence).reduce(0, +) / Double(cleanedLines.count)

        var ambiguities: [DraftAmbiguity] = []
        if titleLine == nil {
            ambiguities.append(DraftAmbiguity(
                field: .title,
                message: "Event title is missing and must be entered.",
                severity: .high
            ))
        }
        if dateEvidence == nil {
            ambiguities.append(DraftAmbiguity(
                field: .dateTime,
                message: "An event date could not be confirmed.",
                severity: .high
            ))
        } else if timeEvidence == nil {
            ambiguities.append(DraftAmbiguity(
                field: .dateTime,
                message: "No clock time was detected, so this is proposed as an all-day event.",
                severity: .medium
            ))
        }
        if locationLine == nil {
            ambiguities.append(DraftAmbiguity(
                field: .location,
                message: "Location was not detected; the event can remain location-free.",
                severity: .low
            ))
        }
        if averageConfidence < 0.65 {
            ambiguities.append(DraftAmbiguity(
                field: .extraction,
                message: "OCR confidence is low. Compare every field with the screenshot.",
                severity: .medium
            ))
        }

        let isAllDay = dateEvidence != nil && timeEvidence == nil
        let startDate = isAllDay
            ? makeDate(dateEvidence: dateEvidence, capturedAt: capturedAt)
            : makeStartDate(
                dateEvidence: dateEvidence,
                timeEvidence: timeEvidence,
                capturedAt: capturedAt
            )
        let startEvidence = [dateEvidence?.line.text, timeEvidence?.line.text]
            .compactMap { $0 }
            .reduce(into: [String]()) { result, item in
                if !result.contains(item) { result.append(item) }
            }
            .joined(separator: " • ")
        let startConfidence = timeEvidence == nil
            ? dateEvidence?.line.confidence ?? 0
            : min(dateEvidence?.line.confidence ?? 0, timeEvidence?.line.confidence ?? 0)
        let endDate: Date?
        let endEvidence: String?
        let endConfidence: Double
        let endIsInferred: Bool
        if isAllDay {
            endDate = makeDate(dateEvidence: endDateEvidence ?? dateEvidence, capturedAt: capturedAt)
            endEvidence = (endDateEvidence ?? dateEvidence)?.line.text
            endConfidence = (endDateEvidence ?? dateEvidence)?.line.confidence ?? 0
            endIsInferred = endDateEvidence == nil
        } else {
            endDate = startDate.flatMap {
                calendar.date(byAdding: .minute, value: defaultDurationMinutes(title: titleLine?.text), to: $0)
            }
            endEvidence = nil
            endConfidence = endDate == nil ? 0 : 0.5
            endIsInferred = endDate != nil
        }

        return EventDraft(
            capturedAt: capturedAt,
            sourceFileName: sourceFileName,
            detectedLanguage: detectLanguage(in: rawText),
            rawOCRText: rawText,
            title: ExtractedField(
                value: titleLine?.text,
                evidenceText: titleLine?.text,
                confidence: titleLine?.confidence ?? 0
            ),
            start: ExtractedField(
                value: startDate,
                evidenceText: startEvidence.isEmpty ? nil : startEvidence,
                confidence: startConfidence,
                isInferred: dateEvidence?.year == nil
            ),
            end: ExtractedField(
                value: endDate,
                evidenceText: endEvidence,
                confidence: endConfidence,
                isInferred: endIsInferred
            ),
            location: ExtractedField(
                value: locationLine?.text,
                evidenceText: locationLine?.text,
                confidence: locationLine?.confidence ?? 0
            ),
            description: ExtractedField(
                value: rawText,
                evidenceText: rawText,
                confidence: averageConfidence
            ),
            isAllDay: isAllDay,
            ambiguities: ambiguities
        )
    }

    private func selectTitle(in lines: [RecognizedTextLine]) -> RecognizedTextLine? {
        let candidates = lines.filter { line in
            parseDate(line) == nil &&
                parseTime(line) == nil &&
                !isLikelyLocation(line) &&
                !isMetadataLine(line) &&
                line.text.count >= 4
        }
        let layoutCandidates = candidates.filter { $0.region != nil }
        guard let maximumHeight = layoutCandidates.compactMap(\.region?.height).max(),
              maximumHeight > 0 else {
            return candidates.first
        }

        let prominent = layoutCandidates
            .filter { ($0.region?.height ?? 0) >= maximumHeight * 0.62 }
            .sorted(by: readingOrder)
        guard let first = prominent.first else { return candidates.first }
        let joined = prominent.map(\.text).joined(separator: " ")
        return RecognizedTextLine(
            text: joined,
            confidence: prominent.map(\.confidence).min() ?? first.confidence,
            region: first.region
        )
    }

    private func readingOrder(_ left: RecognizedTextLine, _ right: RecognizedTextLine) -> Bool {
        guard let leftRegion = left.region, let rightRegion = right.region else {
            return left.text < right.text
        }
        let verticalDelta = (leftRegion.y + leftRegion.height) - (rightRegion.y + rightRegion.height)
        if abs(verticalDelta) > 0.015 { return verticalDelta > 0 }
        return leftRegion.x < rightRegion.x
    }

    private func isMetadataLine(_ line: RecognizedTextLine) -> Bool {
        let folded = line.text.folding(
            options: [.diacriticInsensitive, .caseInsensitive],
            locale: Locale(identifier: "vi_VN")
        ).lowercased()
        let markers = [
            "strategic partner", "enterprise partner", "tech partner", "sponsor",
            "more partners", "announced soon"
        ]
        return markers.contains(where: folded.contains)
    }

    private func defaultDurationMinutes(title: String?) -> Int {
        let folded = (title ?? "").folding(
            options: [.diacriticInsensitive, .caseInsensitive],
            locale: Locale(identifier: "vi_VN")
        ).lowercased()
        if folded.contains("workshop") || folded.contains("seminar") || folded.contains("meetup") {
            return 120
        }
        if folded.contains("concert") || folded.contains("performance") {
            return 180
        }
        return 60
    }

    private func makeStartDate(
        dateEvidence: DateEvidence?,
        timeEvidence: TimeEvidence?,
        capturedAt: Date
    ) -> Date? {
        guard let dateEvidence, let timeEvidence else { return nil }
        let capturedYear = calendar.component(.year, from: capturedAt)
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = normalizedYear(dateEvidence.year) ?? capturedYear
        components.month = dateEvidence.month
        components.day = dateEvidence.day
        components.hour = timeEvidence.hour
        components.minute = timeEvidence.minute
        return calendar.date(from: components)
    }

    private func makeDate(dateEvidence: DateEvidence?, capturedAt: Date) -> Date? {
        guard let dateEvidence else { return nil }
        let capturedYear = calendar.component(.year, from: capturedAt)
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = normalizedYear(dateEvidence.year) ?? capturedYear
        components.month = dateEvidence.month
        components.day = dateEvidence.day
        return calendar.date(from: components).map(calendar.startOfDay(for:))
    }

    private func normalizedYear(_ year: Int?) -> Int? {
        guard let year else { return nil }
        return year < 100 ? 2_000 + year : year
    }

    private func parseDate(_ line: RecognizedTextLine) -> DateEvidence? {
        if let groups = captures(
            #"\b([0-3]?\d)[\/\.\-]([01]?\d)(?:[\/\.\-](\d{2,4}))?\b"#,
            in: line.text
        ),
           let day = integer(groups[safe: 1]),
           let month = integer(groups[safe: 2]),
           (1...31).contains(day),
           (1...12).contains(month) {
            return DateEvidence(
                day: day,
                month: month,
                year: integer(groups[safe: 3]),
                line: line
            )
        }

        if let groups = captures(
            #"\b(january|february|march|april|may|june|july|august|september|october|november|december|jan|feb|mar|apr|jun|jul|aug|sep|sept|oct|nov|dec)\s+([0-3]?\d)(?:st|nd|rd|th)?(?:,?\s+(\d{4}))?\b"#,
            in: line.text
        ),
           let monthName = groups[safe: 1] ?? nil,
           let month = monthNumber(monthName),
           let day = integer(groups[safe: 2]) {
            return DateEvidence(
                day: day,
                month: month,
                year: integer(groups[safe: 3]),
                line: line
            )
        }

        if let groups = captures(
            #"\b([0-3]?\d)\s+(january|february|march|april|may|june|july|august|september|october|november|december|jan|feb|mar|apr|jun|jul|aug|sep|sept|oct|nov|dec)(?:,?\s+(\d{4}))?\b"#,
            in: line.text
        ),
           let day = integer(groups[safe: 1]),
           let monthName = groups[safe: 2] ?? nil,
           let month = monthNumber(monthName) {
            return DateEvidence(
                day: day,
                month: month,
                year: integer(groups[safe: 3]),
                line: line
            )
        }
        return nil
    }

    private func parseDateRange(_ line: RecognizedTextLine) -> DateRangeEvidence? {
        guard let groups = captures(
            #"\b(january|february|march|april|may|june|july|august|september|october|november|december|jan|feb|mar|apr|jun|jul|aug|sep|sept|oct|nov|dec)\s+([0-3]?\d)(?:st|nd|rd|th)?\s*(?:-|–|—|to)\s*(?:(january|february|march|april|may|june|july|august|september|october|november|december|jan|feb|mar|apr|jun|jul|aug|sep|sept|oct|nov|dec)\s+)?([0-3]?\d)(?:st|nd|rd|th)?(?:,?\s+(\d{4}))?\b"#,
            in: line.text
        ),
        let startMonthName = groups[safe: 1] ?? nil,
        let startMonth = monthNumber(startMonthName),
        let startDay = integer(groups[safe: 2]),
        let endDay = integer(groups[safe: 4]) else {
            return nil
        }
        let endMonth = (groups[safe: 3] ?? nil).flatMap(monthNumber) ?? startMonth
        let year = integer(groups[safe: 5])
        return DateRangeEvidence(
            start: DateEvidence(day: startDay, month: startMonth, year: year, line: line),
            end: DateEvidence(day: endDay, month: endMonth, year: year, line: line)
        )
    }

    private func parseStandaloneYear(_ line: RecognizedTextLine) -> Int? {
        guard let groups = captures(#"^\s*(20\d{2})\s*$"#, in: line.text) else { return nil }
        return integer(groups[safe: 1])
    }

    private func parseTime(_ line: RecognizedTextLine) -> TimeEvidence? {
        if let groups = captures(
            #"\b(1[0-2]|0?[1-9])(?::([0-5]\d))?\s*(am|pm)\b"#,
            in: line.text
        ),
           var hour = integer(groups[safe: 1]),
           let meridiem = groups[safe: 3]??.lowercased() {
            if meridiem == "pm" && hour < 12 { hour += 12 }
            if meridiem == "am" && hour == 12 { hour = 0 }
            return TimeEvidence(
                hour: hour,
                minute: integer(groups[safe: 2]) ?? 0,
                line: line
            )
        }

        if let groups = captures(#"\b([01]?\d|2[0-3]):([0-5]\d)\b"#, in: line.text),
           let hour = integer(groups[safe: 1]),
           let minute = integer(groups[safe: 2]) {
            return TimeEvidence(hour: hour, minute: minute, line: line)
        }

        if let groups = captures(#"\b([01]?\d|2[0-3])\s*h(?:\s*([0-5]\d))?\b"#, in: line.text),
           var hour = integer(groups[safe: 1]) {
            let folded = line.text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "vi_VN"))
            if folded.contains("toi") && hour < 12 { hour += 12 }
            return TimeEvidence(
                hour: hour,
                minute: integer(groups[safe: 2]) ?? 0,
                line: line
            )
        }
        return nil
    }

    private func isLikelyLocation(_ line: RecognizedTextLine) -> Bool {
        let folded = line.text.folding(
            options: [.diacriticInsensitive, .caseInsensitive],
            locale: Locale(identifier: "vi_VN")
        ).lowercased()
        let markers = [
            "dai hoc", "university", "dreamplex", "quan ", "district",
            "tp.hcm", "ho chi minh", "zoom", "google meet", "online",
            "nha van hoa", "campus", "auditorium", "street", "duong "
        ]
        return markers.contains(where: folded.contains)
    }

    private func detectLanguage(in text: String) -> DraftLanguage {
        let lowercased = text.lowercased()
        let vietnameseMarkers = ["ngày", "thứ", "đại học", "quận", "giờ", "tối", "sáng"]
        let englishMarkers = ["friday", "saturday", "sunday", "workshop", "meetup", "university", "district"]
        let vietnameseScore = vietnameseMarkers.count(where: lowercased.contains)
        let englishScore = englishMarkers.count(where: lowercased.contains)

        switch (vietnameseScore, englishScore) {
        case (0, 0): return .unknown
        case let (vietnamese, english) where vietnamese > english: return .vietnamese
        case let (vietnamese, english) where english > vietnamese: return .english
        default: return .mixed
        }
    }

    private func captures(_ pattern: String, in text: String) -> [String?]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: fullRange) else {
            return nil
        }
        return (0..<match.numberOfRanges).map { index in
            let range = match.range(at: index)
            guard range.location != NSNotFound, let swiftRange = Range(range, in: text) else {
                return nil
            }
            return String(text[swiftRange])
        }
    }

    private func integer(_ value: String??) -> Int? {
        guard let unwrapped = value ?? nil else { return nil }
        return Int(unwrapped)
    }

    private func monthNumber(_ name: String) -> Int? {
        let key = String(name.lowercased().prefix(3))
        return [
            "jan": 1, "feb": 2, "mar": 3, "apr": 4,
            "may": 5, "jun": 6, "jul": 7, "aug": 8,
            "sep": 9, "oct": 10, "nov": 11, "dec": 12
        ][key]
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
