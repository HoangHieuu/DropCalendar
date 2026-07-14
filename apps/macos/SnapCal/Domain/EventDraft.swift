import Foundation

struct ExtractedField<Value: Equatable>: Equatable {
    var value: Value?
    let evidenceText: String?
    var confidence: Double
    var isInferred: Bool
    var wasEditedByUser: Bool

    init(
        value: Value?,
        evidenceText: String?,
        confidence: Double,
        isInferred: Bool = false,
        wasEditedByUser: Bool = false
    ) {
        self.value = value
        self.evidenceText = evidenceText
        self.confidence = min(max(confidence, 0), 1)
        self.isInferred = isInferred
        self.wasEditedByUser = wasEditedByUser
    }

    mutating func applyUserEdit(_ newValue: Value) {
        value = newValue
        confidence = 1
        isInferred = false
        wasEditedByUser = true
    }
}

enum AmbiguityField: String, Equatable {
    case title
    case dateTime
    case endTime
    case location
    case extraction
}

enum AmbiguitySeverity: String, Equatable {
    case low
    case medium
    case high
}

struct DraftAmbiguity: Identifiable, Equatable {
    let id: UUID
    let field: AmbiguityField
    let message: String
    let severity: AmbiguitySeverity

    init(
        id: UUID = UUID(),
        field: AmbiguityField,
        message: String,
        severity: AmbiguitySeverity
    ) {
        self.id = id
        self.field = field
        self.message = message
        self.severity = severity
    }
}

enum DraftLanguage: String, Equatable {
    case vietnamese
    case english
    case mixed
    case unknown
}

struct EventDraft: Identifiable, Equatable {
    let id: UUID
    let createdAt: Date
    let capturedAt: Date
    let sourceFileName: String
    var sourceFingerprint: String?
    let detectedLanguage: DraftLanguage
    let rawOCRText: String

    var title: ExtractedField<String>
    var start: ExtractedField<Date>
    var end: ExtractedField<Date>
    var location: ExtractedField<String>
    var description: ExtractedField<String>
    var reminders: [EventReminder]
    var isAllDay: Bool
    var ambiguities: [DraftAmbiguity]
    let requiresUserConfirmation: Bool

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        capturedAt: Date,
        sourceFileName: String,
        sourceFingerprint: String? = nil,
        detectedLanguage: DraftLanguage,
        rawOCRText: String,
        title: ExtractedField<String>,
        start: ExtractedField<Date>,
        end: ExtractedField<Date>,
        location: ExtractedField<String>,
        description: ExtractedField<String>,
        reminders: [EventReminder] = [],
        isAllDay: Bool = false,
        ambiguities: [DraftAmbiguity],
        requiresUserConfirmation: Bool = true
    ) {
        self.id = id
        self.createdAt = createdAt
        self.capturedAt = capturedAt
        self.sourceFileName = sourceFileName
        self.sourceFingerprint = sourceFingerprint
        self.detectedLanguage = detectedLanguage
        self.rawOCRText = rawOCRText
        self.title = title
        self.start = start
        self.end = end
        self.location = location
        self.description = description
        self.reminders = reminders
        self.isAllDay = isAllDay
        self.ambiguities = ambiguities
        self.requiresUserConfirmation = requiresUserConfirmation
    }

    static let empty = EventDraft(
        capturedAt: Date(),
        sourceFileName: "",
        detectedLanguage: .unknown,
        rawOCRText: "",
        title: ExtractedField(value: nil, evidenceText: nil, confidence: 0),
        start: ExtractedField(value: nil, evidenceText: nil, confidence: 0),
        end: ExtractedField(value: nil, evidenceText: nil, confidence: 0),
        location: ExtractedField(value: nil, evidenceText: nil, confidence: 0),
        description: ExtractedField(value: nil, evidenceText: nil, confidence: 0),
        ambiguities: []
    )
}
