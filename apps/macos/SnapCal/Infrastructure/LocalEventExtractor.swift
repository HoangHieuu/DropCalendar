import Foundation

protocol EventExtracting {
    func extract(
        lines: [RecognizedTextLine],
        capturedAt: Date,
        sourceFileName: String
    ) throws -> EventDraft

    func extractEvents(
        lines: [RecognizedTextLine],
        capturedAt: Date,
        sourceFileName: String
    ) throws -> [EventDraft]
}

extension EventExtracting {
    func extractEvents(
        lines: [RecognizedTextLine],
        capturedAt: Date,
        sourceFileName: String
    ) throws -> [EventDraft] {
        [try extract(
            lines: lines,
            capturedAt: capturedAt,
            sourceFileName: sourceFileName
        )]
    }
}

enum DraftExtractionError: LocalizedError, Equatable {
    case noEventDetected

    var errorDescription: String? {
        "No reliable date or time evidence was found. Try a clearer event screenshot."
    }
}

struct LocalEventExtractor: EventExtracting {
    private struct NumberedEventBlock {
        let ordinal: Int
        let lines: [RecognizedTextLine]
    }

    private struct DateEvidence {
        let day: Int
        let month: Int
        let year: Int?
        let line: RecognizedTextLine
        let isInferred: Bool

        init(
            day: Int,
            month: Int,
            year: Int?,
            line: RecognizedTextLine,
            isInferred: Bool = false
        ) {
            self.day = day
            self.month = month
            self.year = year
            self.line = line
            self.isInferred = isInferred
        }
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

    func extractEvents(
        lines: [RecognizedTextLine],
        capturedAt: Date,
        sourceFileName: String
    ) throws -> [EventDraft] {
        let blocks = numberedEventBlocks(in: lines)
        guard blocks.count >= 2 else {
            return [try extract(
                lines: lines,
                capturedAt: capturedAt,
                sourceFileName: sourceFileName
            )]
        }

        return try blocks.prefix(10).map { block in
            var draft = try extract(
                lines: block.lines,
                capturedAt: capturedAt,
                sourceFileName: sourceFileName
            )
            if let title = conciseNumberedTitle(in: block.lines, ordinal: block.ordinal) {
                draft.title = ExtractedField(
                    value: title.text,
                    evidenceText: title.evidence,
                    confidence: title.confidence
                )
            }
            return draft
        }
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

        let timeCandidates = cleanedLines.compactMap(parseTime)
        let timeEvidence = selectTimeEvidence(timeCandidates)
        let explicitRange = cleanedLines.compactMap(parseDateRange).first
        let standaloneYear = cleanedLines.compactMap(parseStandaloneYear).first
        let explicitDateCandidates = cleanedLines.compactMap(parseDate).map {
            DateEvidence(
                day: $0.day,
                month: $0.month,
                year: $0.year ?? standaloneYear,
                line: $0.line
            )
        }
        let relativeDateCandidates = cleanedLines.compactMap {
            parseRelativeDate($0, capturedAt: capturedAt, timeEvidence: timeEvidence)
        }
        let dateCandidates = explicitDateCandidates + relativeDateCandidates
        let dateEvidence = explicitRange?.start ?? selectDateEvidence(dateCandidates)
        let endDateEvidence = explicitRange?.end ?? selectLayoutRangeEnd(
            explicitDateCandidates,
            selectedStart: dateEvidence,
            hasClockTime: timeEvidence != nil
        )
        guard dateEvidence != nil || timeEvidence != nil else {
            throw DraftExtractionError.noEventDetected
        }

        let locationLine = selectLocation(in: cleanedLines)
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
        let distinctExplicitDates = Set(explicitDateCandidates.map {
            "\($0.year ?? 0)-\($0.month)-\($0.day)"
        })
        if explicitRange == nil && distinctExplicitDates.count > 1 {
            ambiguities.append(DraftAmbiguity(
                field: .dateTime,
                message: "Multiple possible dates were detected. SnapCal preferred the line that looks most like the event date; verify it against the screenshot.",
                severity: .high
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
        var startConfidence = timeEvidence == nil
            ? dateEvidence?.line.confidence ?? 0
            : min(dateEvidence?.line.confidence ?? 0, timeEvidence?.line.confidence ?? 0)
        if let startDate,
           let statedWeekday = cleanedLines.compactMap(parseWeekday).first,
           calendar.component(.weekday, from: startDate) != statedWeekday {
            ambiguities.append(DraftAmbiguity(
                field: .dateTime,
                message: "The stated weekday conflicts with the proposed date. Choose the correct date before creating the event.",
                severity: .high
            ))
            startConfidence = min(startConfidence, 0.49)
        }
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
                isInferred: dateEvidence?.isInferred == true || dateEvidence?.year == nil
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

    private func numberedEventBlocks(in lines: [RecognizedTextLine]) -> [NumberedEventBlock] {
        let cleaned = lines
            .map {
                RecognizedTextLine(
                    text: $0.text.trimmingCharacters(in: .whitespacesAndNewlines),
                    confidence: $0.confidence,
                    region: $0.region
                )
            }
            .filter { !$0.text.isEmpty }

        var blocks: [NumberedEventBlock] = []
        var currentOrdinal: Int?
        var currentLines: [RecognizedTextLine] = []

        func finishCurrentBlock() {
            guard let ordinal = currentOrdinal, !currentLines.isEmpty else { return }
            blocks.append(NumberedEventBlock(ordinal: ordinal, lines: currentLines))
        }

        for line in cleaned {
            if let numbered = numberedLine(line) {
                finishCurrentBlock()
                currentOrdinal = numbered.ordinal
                currentLines = [numbered.line]
            } else if currentOrdinal != nil {
                currentLines.append(line)
            }
        }
        finishCurrentBlock()

        let independentlyDated = blocks.filter { block in
            block.lines.contains { parseDate($0) != nil || parseDateRange($0) != nil }
        }
        guard independentlyDated.count >= 2,
              independentlyDated.count == blocks.count else {
            return []
        }
        return independentlyDated
    }

    private func numberedLine(
        _ line: RecognizedTextLine
    ) -> (ordinal: Int, line: RecognizedTextLine)? {
        guard let groups = captures(#"^\s*(\d{1,2})\s*[\)\.\:\-]\s*(.+)$"#, in: line.text),
              let ordinal = integer(groups[safe: 1]),
              let text = groups[safe: 2] ?? nil,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return (
            ordinal,
            RecognizedTextLine(
                text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                confidence: line.confidence,
                region: line.region
            )
        )
    }

    private func conciseNumberedTitle(
        in lines: [RecognizedTextLine],
        ordinal: Int
    ) -> (text: String, evidence: String, confidence: Double)? {
        let patterns = [
            #"\b(?:buổi\s+)?training(?:\s+cho)?\s+bài\s+\d+\b"#,
            #"\btraining\s+(?:session|lesson|part|module)\s+\d+\b"#,
            #"\b(?:session|lesson|part|module)\s+\d+\b"#,
        ]
        for line in lines {
            for pattern in patterns {
                guard let regex = try? NSRegularExpression(
                    pattern: pattern,
                    options: [.caseInsensitive]
                ) else { continue }
                let range = NSRange(line.text.startIndex..<line.text.endIndex, in: line.text)
                guard let match = regex.firstMatch(in: line.text, range: range),
                      let swiftRange = Range(match.range, in: line.text) else {
                    continue
                }
                return (
                    String(line.text[swiftRange]).trimmingCharacters(in: .whitespacesAndNewlines),
                    line.text,
                    line.confidence
                )
            }
        }

        guard let first = lines.first else { return nil }
        return (
            "Event \(ordinal): \(first.text)",
            first.text,
            min(first.confidence, 0.7)
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

    private func selectDateEvidence(_ candidates: [DateEvidence]) -> DateEvidence? {
        candidates.max { left, right in
            dateRelevanceScore(left.line) < dateRelevanceScore(right.line)
        }
    }

    private func selectLayoutRangeEnd(
        _ candidates: [DateEvidence],
        selectedStart: DateEvidence?,
        hasClockTime: Bool
    ) -> DateEvidence? {
        guard !hasClockTime,
              candidates.count == 2,
              let selectedStart,
              let startIndex = candidates.firstIndex(where: {
                  $0.day == selectedStart.day &&
                      $0.month == selectedStart.month &&
                      $0.year == selectedStart.year
              }),
              let startRegion = candidates[startIndex].line.region else {
            return nil
        }
        let endIndex = startIndex == 0 ? 1 : 0
        let candidate = candidates[endIndex]
        guard let endRegion = candidate.line.region,
              abs(startRegion.y - endRegion.y) <= 0.02,
              dateRelevanceScore(selectedStart.line) == dateRelevanceScore(candidate.line),
              candidate.month > selectedStart.month ||
                (candidate.month == selectedStart.month && candidate.day >= selectedStart.day) else {
            return nil
        }
        return candidate
    }

    private func dateRelevanceScore(_ line: RecognizedTextLine) -> Int {
        let folded = foldedText(line.text)
        var score = parseTime(line) == nil ? 0 : 2
        let eventMarkers = [
            "event", "su kien", "chuong trinh", "show starts", "starts at",
            "begins at", "bat dau", "khai mac"
        ]
        let deadlineMarkers = [
            "register by", "registration", "deadline", "apply by",
            "dang ky truoc", "han dang ky", "early bird"
        ]
        if eventMarkers.contains(where: folded.contains) { score += 6 }
        if deadlineMarkers.contains(where: folded.contains) { score -= 8 }
        return score
    }

    private func selectTimeEvidence(_ candidates: [TimeEvidence]) -> TimeEvidence? {
        candidates.max { left, right in
            timeRelevanceScore(left.line) < timeRelevanceScore(right.line)
        }
    }

    private func timeRelevanceScore(_ line: RecognizedTextLine) -> Int {
        let folded = foldedText(line.text)
        var score = 0
        let startMarkers = [
            "show starts", "event starts", "starts at", "begins at",
            "bat dau", "khai mac", "su kien luc"
        ]
        let secondaryMarkers = ["doors open", "check-in", "check in", "don khach"]
        if startMarkers.contains(where: folded.contains) { score += 8 }
        if secondaryMarkers.contains(where: folded.contains) { score -= 5 }
        return score
    }

    private func selectLocation(in lines: [RecognizedTextLine]) -> RecognizedTextLine? {
        lines
            .filter { isLikelyLocation($0) && !isMetadataLine($0) }
            .max { left, right in
                locationRelevanceScore(left) < locationRelevanceScore(right)
            }
    }

    private func locationRelevanceScore(_ line: RecognizedTextLine) -> Int {
        let folded = foldedText(line.text)
        var score = min(line.text.count / 8, 5)
        let specificMarkers = [
            "tp.hcm", "ho chi minh", "district", "quan ", "duong ", "street",
            "campus", "auditorium", "dreamplex", "bach khoa", "zoom",
            "google meet", "online"
        ]
        score += specificMarkers.count(where: folded.contains) * 3
        return score
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
        let folded = foldedText(line.text)
        let exactLabels = [
            "facebook", "tiktok", "instagram", "website", "university",
            "workshop", "hackathon", "concert", "webinar", "online event"
        ]
        if exactLabels.contains(folded.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return true
        }
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
            #"\bngay\s+([0-3]?\d)\s+thang\s+([01]?\d)(?:\s+(?:nam\s+)?(\d{2,4}))?\b"#,
            in: foldedText(line.text)
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
        let folded = foldedText(line.text)
        let semanticStartPatterns = [
            #"show\s+starts?"#, #"event\s+starts?"#, #"starts?\s+at"#,
            #"begins?\s+at"#, #"bat\s+dau"#, #"khai\s+mac"#
        ]
        for pattern in semanticStartPatterns {
            if let range = folded.range(of: pattern, options: .regularExpression),
               let result = parseBasicTime(in: String(folded[range.lowerBound...]), line: line) {
                return result
            }
        }
        return parseBasicTime(in: folded, line: line)
    }

    private func parseBasicTime(in text: String, line: RecognizedTextLine) -> TimeEvidence? {
        if let groups = captures(
            #"\b(1[0-2]|0?[1-9])(?::([0-5]\d))?\s*(am|pm)\b"#,
            in: text
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

        if let groups = captures(#"\b([01]?\d|2[0-3]):([0-5]\d)\b"#, in: text),
           let hour = integer(groups[safe: 1]),
           let minute = integer(groups[safe: 2]) {
            return TimeEvidence(hour: hour, minute: minute, line: line)
        }

        if line.confidence >= 0.90,
           let groups = captures(#"\b([01]?\d|2[0-3])\s*:\s*o[o0]\b"#, in: text),
           let hour = integer(groups[safe: 1]) {
            return TimeEvidence(hour: hour, minute: 0, line: line)
        }

        if let groups = captures(#"\b([01]?\d|2[0-3])\s*(?:h|gio)(?:\s*([0-5]\d))?\b"#, in: text),
           var hour = integer(groups[safe: 1]) {
            if text.contains("toi") && hour < 12 { hour += 12 }
            if text.contains("sang") && hour == 12 { hour = 0 }
            return TimeEvidence(
                hour: hour,
                minute: integer(groups[safe: 2]) ?? 0,
                line: line
            )
        }
        return nil
    }

    private func parseRelativeDate(
        _ line: RecognizedTextLine,
        capturedAt: Date,
        timeEvidence: TimeEvidence?
    ) -> DateEvidence? {
        let folded = foldedText(line.text)
        let dayOffset: Int?
        if folded.contains("tomorrow") || folded.contains("ngay mai") {
            dayOffset = 1
        } else if folded.contains("today") || folded.contains("tonight") ||
                    folded.contains("hom nay") || folded.contains("toi nay") {
            dayOffset = 0
        } else if let weekday = parseWeekday(line), timeEvidence != nil {
            let currentWeekday = calendar.component(.weekday, from: capturedAt)
            var offset = (weekday - currentWeekday + 7) % 7
            if offset == 0,
               let timeEvidence,
               let proposedToday = calendar.date(
                   bySettingHour: timeEvidence.hour,
                   minute: timeEvidence.minute,
                   second: 0,
                   of: capturedAt
               ),
               proposedToday <= capturedAt {
                offset = 7
            }
            dayOffset = offset
        } else {
            return nil
        }

        guard let dayOffset,
              let resolved = calendar.date(byAdding: .day, value: dayOffset, to: capturedAt) else {
            return nil
        }
        let components = calendar.dateComponents([.year, .month, .day], from: resolved)
        guard let year = components.year,
              let month = components.month,
              let day = components.day else {
            return nil
        }
        return DateEvidence(
            day: day,
            month: month,
            year: year,
            line: line,
            isInferred: true
        )
    }

    private func parseWeekday(_ line: RecognizedTextLine) -> Int? {
        let folded = foldedText(line.text)
        let patterns: [(String, Int)] = [
            (#"\b(sunday|chu\s*nhat|cn)\b"#, 1),
            (#"\b(monday|thu\s*(?:2|hai)|t2)\b"#, 2),
            (#"\b(tuesday|thu\s*(?:3|ba)|t3)\b"#, 3),
            (#"\b(wednesday|thu\s*(?:4|tu)|t4)\b"#, 4),
            (#"\b(thursday|thu\s*(?:5|nam)|t5)\b"#, 5),
            (#"\b(friday|thu\s*(?:6|sau)|t6)\b"#, 6),
            (#"\b(saturday|thu\s*(?:7|bay)|t7)\b"#, 7),
        ]
        return patterns.first(where: {
            folded.range(of: $0.0, options: .regularExpression) != nil
        })?.1
    }

    private func isLikelyLocation(_ line: RecognizedTextLine) -> Bool {
        let folded = foldedText(line.text)
        let markers = [
            "dai hoc", "university", "dreamplex", "quan ", "district",
            "tp.hcm", "ho chi minh", "zoom", "google meet", "online",
            "nha van hoa", "campus", "auditorium", "street", "duong ",
            "dia diem", "venue"
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

    private func foldedText(_ text: String) -> String {
        text.folding(
            options: [.diacriticInsensitive, .caseInsensitive],
            locale: Locale(identifier: "vi_VN")
        ).lowercased()
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
