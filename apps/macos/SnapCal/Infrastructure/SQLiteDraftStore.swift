import Foundation
import SQLite3

enum DraftLifecycle: String, Codable, Sendable {
    case draft
    case created
}

struct RecentDraftSummary: Identifiable, Equatable, Sendable {
    let id: UUID
    let title: String
    let start: Date?
    let location: String?
    let updatedAt: Date
    let lifecycle: DraftLifecycle
}

struct PersistedDraft: Codable, Equatable, Sendable {
    struct StringField: Codable, Equatable, Sendable {
        let value: String?
        let evidenceText: String?
        let confidence: Double
        let isInferred: Bool
        let wasEditedByUser: Bool
    }

    struct DateField: Codable, Equatable, Sendable {
        let value: Date?
        let evidenceText: String?
        let confidence: Double
        let isInferred: Bool
        let wasEditedByUser: Bool
    }

    struct Ambiguity: Codable, Equatable, Sendable {
        let id: UUID
        let field: String
        let message: String
        let severity: String
    }

    struct Source: Codable, Equatable, Sendable {
        enum Kind: String, Codable, Sendable {
            // Legacy values remain decodable for drafts saved before Local Semantic.
            case local
            case openRouter
            case localFallback
            case localSemantic
            case localSemanticFallback
            case accuracyFallback
        }

        let kind: Kind
        let model: String?
        let reason: String?

        init(kind: Kind, model: String? = nil, reason: String? = nil) {
            self.kind = kind
            self.model = model
            self.reason = reason
        }
    }

    struct Receipt: Codable, Equatable, Sendable {
        let providerEventID: String
        let calendarLink: String?
    }

    static let currentPayloadVersion = 1

    let payloadVersion: Int
    let id: UUID
    let createdAt: Date
    let updatedAt: Date
    let capturedAt: Date
    let sourceFileName: String
    let sourceFingerprint: String?
    let detectedLanguage: String
    let title: StringField
    let start: DateField
    let end: DateField
    let location: StringField
    let eventDescription: StringField
    let reminders: [EventReminder]
    let isAllDay: Bool
    let ambiguities: [Ambiguity]
    let requiresUserConfirmation: Bool
    let extractionSource: Source
    let lifecycle: DraftLifecycle
    let receipt: Receipt?

    private enum CodingKeys: String, CodingKey {
        case payloadVersion
        case id
        case createdAt
        case updatedAt
        case capturedAt
        case sourceFileName
        case sourceFingerprint
        case detectedLanguage
        case title
        case start
        case end
        case location
        case eventDescription
        case reminders
        case isAllDay
        case ambiguities
        case requiresUserConfirmation
        case extractionSource
        case lifecycle
        case receipt
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        payloadVersion = try container.decode(Int.self, forKey: .payloadVersion)
        id = try container.decode(UUID.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        capturedAt = try container.decode(Date.self, forKey: .capturedAt)
        sourceFileName = try container.decode(String.self, forKey: .sourceFileName)
        sourceFingerprint = try container.decodeIfPresent(
            String.self,
            forKey: .sourceFingerprint
        )
        detectedLanguage = try container.decode(String.self, forKey: .detectedLanguage)
        title = try container.decode(StringField.self, forKey: .title)
        start = try container.decode(DateField.self, forKey: .start)
        end = try container.decode(DateField.self, forKey: .end)
        location = try container.decode(StringField.self, forKey: .location)
        eventDescription = try container.decode(StringField.self, forKey: .eventDescription)
        reminders = try container.decodeIfPresent(
            [EventReminder].self,
            forKey: .reminders
        ) ?? []
        isAllDay = try container.decode(Bool.self, forKey: .isAllDay)
        ambiguities = try container.decode([Ambiguity].self, forKey: .ambiguities)
        requiresUserConfirmation = try container.decode(
            Bool.self,
            forKey: .requiresUserConfirmation
        )
        extractionSource = try container.decode(Source.self, forKey: .extractionSource)
        lifecycle = try container.decode(DraftLifecycle.self, forKey: .lifecycle)
        receipt = try container.decodeIfPresent(Receipt.self, forKey: .receipt)
    }

    init(
        draft: EventDraft,
        updatedAt: Date = Date(),
        extractionNotice: ExtractionNotice,
        lifecycle: DraftLifecycle,
        receipt: CalendarCreationReceipt?
    ) {
        payloadVersion = Self.currentPayloadVersion
        id = draft.id
        createdAt = draft.createdAt
        self.updatedAt = updatedAt
        capturedAt = draft.capturedAt
        sourceFileName = draft.sourceFileName
        sourceFingerprint = draft.sourceFingerprint
        detectedLanguage = draft.detectedLanguage.rawValue
        title = Self.stringField(draft.title)
        start = Self.dateField(draft.start)
        end = Self.dateField(draft.end)
        location = Self.stringField(draft.location)
        eventDescription = Self.stringField(draft.description)
        reminders = draft.reminders
        isAllDay = draft.isAllDay
        ambiguities = draft.ambiguities.map {
            Ambiguity(
                id: $0.id,
                field: $0.field.rawValue,
                message: $0.message,
                severity: $0.severity.rawValue
            )
        }
        requiresUserConfirmation = draft.requiresUserConfirmation
        switch extractionNotice {
        case .localSemantic(let model):
            extractionSource = Source(kind: .localSemantic, model: model)
        case .localSemanticFallback(let reason):
            extractionSource = Source(
                kind: .localSemanticFallback,
                reason: reason
            )
        case .openRouter(let model):
            extractionSource = Source(kind: .openRouter, model: model)
        case .accuracyFallback(let reason):
            extractionSource = Source(kind: .accuracyFallback, reason: reason)
        }
        self.lifecycle = lifecycle
        self.receipt = receipt.map {
            Receipt(
                providerEventID: $0.providerEventID,
                calendarLink: $0.calendarLink?.absoluteString
            )
        }
    }

    var summary: RecentDraftSummary {
        RecentDraftSummary(
            id: id,
            title: title.value?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
                ?? "Untitled event",
            start: start.value,
            location: location.value?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty,
            updatedAt: updatedAt,
            lifecycle: lifecycle
        )
    }

    func restore() throws -> (EventDraft, ExtractionNotice, CalendarCreationReceipt?) {
        guard payloadVersion == Self.currentPayloadVersion else {
            throw DraftStoreError.unsupportedPayloadVersion
        }
        let language = DraftLanguage(rawValue: detectedLanguage) ?? .unknown
        let restoredAmbiguities = ambiguities.compactMap { ambiguity -> DraftAmbiguity? in
            guard
                let field = AmbiguityField(rawValue: ambiguity.field),
                let severity = AmbiguitySeverity(rawValue: ambiguity.severity)
            else { return nil }
            return DraftAmbiguity(
                id: ambiguity.id,
                field: field,
                message: ambiguity.message,
                severity: severity
            )
        }
        guard restoredAmbiguities.count == ambiguities.count else {
            throw DraftStoreError.invalidRecord
        }

        let draft = EventDraft(
            id: id,
            createdAt: createdAt,
            capturedAt: capturedAt,
            sourceFileName: sourceFileName,
            sourceFingerprint: sourceFingerprint,
            detectedLanguage: language,
            rawOCRText: "",
            title: Self.restore(title),
            start: Self.restore(start),
            end: Self.restore(end),
            location: Self.restore(location),
            description: Self.restore(eventDescription),
            reminders: reminders,
            isAllDay: isAllDay,
            ambiguities: restoredAmbiguities,
            requiresUserConfirmation: requiresUserConfirmation
        )
        let notice: ExtractionNotice
        switch extractionSource.kind {
        case .local:
            notice = .localSemanticFallback(
                reason: "This saved draft used deterministic local extraction before Local Semantic was introduced."
            )
        case .openRouter:
            notice = .openRouter(model: extractionSource.model ?? "OpenRouter")
        case .localFallback:
            notice = .accuracyFallback(
                reason: "This saved Accuracy draft used the deterministic on-device fallback."
            )
        case .localSemantic:
            notice = .localSemantic(
                model: extractionSource.model ?? "Apple Foundation Models"
            )
        case .localSemanticFallback:
            notice = .localSemanticFallback(
                reason: extractionSource.reason
                    ?? "This saved draft used deterministic on-device extraction."
            )
        case .accuracyFallback:
            notice = .accuracyFallback(
                reason: extractionSource.reason
                    ?? "This saved Accuracy draft used deterministic on-device extraction."
            )
        }
        let restoredReceipt = receipt.map {
            CalendarCreationReceipt(
                providerEventID: $0.providerEventID,
                calendarLink: $0.calendarLink.flatMap(URL.init(string:))
            )
        }
        return (draft, notice, restoredReceipt)
    }

    var duplicateSignature: DuplicateSignature {
        DuplicateSignature(
            id: id,
            sourceFingerprint: sourceFingerprint,
            title: title.value,
            start: start.value,
            location: location.value
        )
    }

    private static func stringField(_ field: ExtractedField<String>) -> StringField {
        StringField(
            value: field.value,
            evidenceText: field.evidenceText,
            confidence: field.confidence,
            isInferred: field.isInferred,
            wasEditedByUser: field.wasEditedByUser
        )
    }

    private static func dateField(_ field: ExtractedField<Date>) -> DateField {
        DateField(
            value: field.value,
            evidenceText: field.evidenceText,
            confidence: field.confidence,
            isInferred: field.isInferred,
            wasEditedByUser: field.wasEditedByUser
        )
    }

    private static func restore(_ field: StringField) -> ExtractedField<String> {
        ExtractedField(
            value: field.value,
            evidenceText: field.evidenceText,
            confidence: field.confidence,
            isInferred: field.isInferred,
            wasEditedByUser: field.wasEditedByUser
        )
    }

    private static func restore(_ field: DateField) -> ExtractedField<Date> {
        ExtractedField(
            value: field.value,
            evidenceText: field.evidenceText,
            confidence: field.confidence,
            isInferred: field.isInferred,
            wasEditedByUser: field.wasEditedByUser
        )
    }
}

protocol DraftPersisting: Sendable {
    func save(_ draft: PersistedDraft) async throws
    func recent(limit: Int) async throws -> [RecentDraftSummary]
    func load(id: UUID) async throws -> PersistedDraft?
    func duplicateWarnings(for draft: PersistedDraft) async throws -> [DuplicateWarning]
    func delete(id: UUID) async throws
    func deleteAll() async throws
}

enum DraftStoreError: LocalizedError, Equatable {
    case unavailable
    case migrationFailed
    case newerSchema
    case unsupportedPayloadVersion
    case invalidRecord

    var errorDescription: String? {
        switch self {
        case .newerSchema:
            return "Recent drafts were created by a newer SnapCal version."
        case .unsupportedPayloadVersion, .invalidRecord:
            return "A recent draft could not be read safely."
        case .unavailable, .migrationFailed:
            return "Recent drafts are temporarily unavailable."
        }
    }
}

struct DisabledDraftStore: DraftPersisting {
    func save(_ draft: PersistedDraft) async throws { }
    func recent(limit: Int) async throws -> [RecentDraftSummary] { [] }
    func load(id: UUID) async throws -> PersistedDraft? { nil }
    func duplicateWarnings(for draft: PersistedDraft) async throws -> [DuplicateWarning] { [] }
    func delete(id: UUID) async throws { }
    func deleteAll() async throws { }
}

struct UnavailableDraftStore: DraftPersisting {
    func save(_ draft: PersistedDraft) async throws { throw DraftStoreError.unavailable }
    func recent(limit: Int) async throws -> [RecentDraftSummary] { throw DraftStoreError.unavailable }
    func load(id: UUID) async throws -> PersistedDraft? { throw DraftStoreError.unavailable }
    func duplicateWarnings(for draft: PersistedDraft) async throws -> [DuplicateWarning] { throw DraftStoreError.unavailable }
    func delete(id: UUID) async throws { throw DraftStoreError.unavailable }
    func deleteAll() async throws { throw DraftStoreError.unavailable }
}

actor SQLiteDraftStore: DraftPersisting {
    static let schemaVersion = 2
    static let defaultRecentLimit = 20

    private let databaseURL: URL
    private var database: OpaquePointer?
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(databaseURL: URL) throws {
        self.databaseURL = databaseURL
        encoder = JSONEncoder()
        decoder = JSONDecoder()

        try Self.prepareDirectory(for: databaseURL)
        var openedDatabase: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(databaseURL.path, &openedDatabase, flags, nil) == SQLITE_OK,
              let openedDatabase else {
            if let openedDatabase { sqlite3_close(openedDatabase) }
            throw DraftStoreError.unavailable
        }
        database = openedDatabase

        do {
            sqlite3_busy_timeout(openedDatabase, 2_000)
            try Self.execute(openedDatabase, sql: "PRAGMA journal_mode=WAL;")
            try Self.execute(openedDatabase, sql: "PRAGMA synchronous=NORMAL;")
            try Self.migrate(openedDatabase)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: databaseURL.path
            )
        } catch {
            sqlite3_close(openedDatabase)
            database = nil
            throw error
        }
    }

    deinit {
        if let database { sqlite3_close(database) }
    }

    static func live() throws -> SQLiteDraftStore {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return try SQLiteDraftStore(
            databaseURL: support
                .appendingPathComponent("SnapCal", isDirectory: true)
                .appendingPathComponent("snapcal.sqlite3")
        )
    }

    func save(_ draft: PersistedDraft) async throws {
        guard let database else { throw DraftStoreError.unavailable }
        let payload: Data
        do {
            payload = try encoder.encode(draft)
        } catch {
            throw DraftStoreError.invalidRecord
        }
        let sql = """
        INSERT INTO drafts (
            id, created_at, updated_at, event_start, normalized_title,
            normalized_location, source_fingerprint, lifecycle, payload_version, payload
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            updated_at = excluded.updated_at,
            event_start = excluded.event_start,
            normalized_title = excluded.normalized_title,
            normalized_location = excluded.normalized_location,
            source_fingerprint = excluded.source_fingerprint,
            lifecycle = excluded.lifecycle,
            payload_version = excluded.payload_version,
            payload = excluded.payload;
        """
        let statement = try Self.prepare(database, sql: sql)
        defer { sqlite3_finalize(statement) }

        Self.bind(draft.id.uuidString, to: statement, at: 1)
        sqlite3_bind_double(statement, 2, draft.createdAt.timeIntervalSince1970)
        sqlite3_bind_double(statement, 3, draft.updatedAt.timeIntervalSince1970)
        Self.bind(draft.start.value?.timeIntervalSince1970, to: statement, at: 4)
        Self.bind(Self.normalized(draft.title.value), to: statement, at: 5)
        Self.bind(Self.normalized(draft.location.value), to: statement, at: 6)
        Self.bind(draft.sourceFingerprint, to: statement, at: 7)
        Self.bind(draft.lifecycle.rawValue, to: statement, at: 8)
        sqlite3_bind_int(statement, 9, Int32(draft.payloadVersion))
        Self.bind(payload, to: statement, at: 10)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw DraftStoreError.unavailable
        }
    }

    func recent(limit: Int = SQLiteDraftStore.defaultRecentLimit) async throws -> [RecentDraftSummary] {
        guard let database else { throw DraftStoreError.unavailable }
        let safeLimit = min(max(limit, 1), 100)
        let statement = try Self.prepare(
            database,
            sql: "SELECT payload FROM drafts ORDER BY updated_at DESC LIMIT ?;"
        )
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int(statement, 1, Int32(safeLimit))

        var summaries: [RecentDraftSummary] = []
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                let payload = try Self.data(from: statement, column: 0)
                let draft: PersistedDraft
                do {
                    draft = try decoder.decode(PersistedDraft.self, from: payload)
                } catch {
                    throw DraftStoreError.invalidRecord
                }
                guard draft.payloadVersion == PersistedDraft.currentPayloadVersion else {
                    throw DraftStoreError.unsupportedPayloadVersion
                }
                summaries.append(draft.summary)
            case SQLITE_DONE:
                return summaries
            default:
                throw DraftStoreError.unavailable
            }
        }
    }

    func load(id: UUID) async throws -> PersistedDraft? {
        guard let database else { throw DraftStoreError.unavailable }
        let statement = try Self.prepare(
            database,
            sql: "SELECT payload FROM drafts WHERE id = ? LIMIT 1;"
        )
        defer { sqlite3_finalize(statement) }
        Self.bind(id.uuidString, to: statement, at: 1)

        switch sqlite3_step(statement) {
        case SQLITE_DONE:
            return nil
        case SQLITE_ROW:
            let payload = try Self.data(from: statement, column: 0)
            do {
                let draft = try decoder.decode(PersistedDraft.self, from: payload)
                guard draft.id == id else { throw DraftStoreError.invalidRecord }
                _ = try draft.restore()
                return draft
            } catch let error as DraftStoreError {
                throw error
            } catch {
                throw DraftStoreError.invalidRecord
            }
        default:
            throw DraftStoreError.unavailable
        }
    }

    func duplicateWarnings(for draft: PersistedDraft) async throws -> [DuplicateWarning] {
        guard let database else { throw DraftStoreError.unavailable }
        let statement = try Self.prepare(
            database,
            sql: "SELECT payload FROM drafts WHERE id != ? ORDER BY updated_at DESC LIMIT 100;"
        )
        defer { sqlite3_finalize(statement) }
        Self.bind(draft.id.uuidString, to: statement, at: 1)

        var history: [DuplicateSignature] = []
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                let payload = try Self.data(from: statement, column: 0)
                let existing: PersistedDraft
                do {
                    existing = try decoder.decode(PersistedDraft.self, from: payload)
                } catch {
                    throw DraftStoreError.invalidRecord
                }
                history.append(existing.duplicateSignature)
            case SQLITE_DONE:
                return DuplicateDetector.warnings(
                    for: draft.duplicateSignature,
                    among: history
                )
            default:
                throw DraftStoreError.unavailable
            }
        }
    }

    func delete(id: UUID) async throws {
        guard let database else { throw DraftStoreError.unavailable }
        let statement = try Self.prepare(
            database,
            sql: "DELETE FROM drafts WHERE id = ?;"
        )
        defer { sqlite3_finalize(statement) }
        Self.bind(id.uuidString, to: statement, at: 1)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw DraftStoreError.unavailable
        }
    }

    func deleteAll() async throws {
        guard let database else { throw DraftStoreError.unavailable }
        try Self.execute(database, sql: "DELETE FROM drafts;")
    }

    private static func prepareDirectory(for databaseURL: URL) throws {
        let directory = databaseURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: directory.path
            )
        } catch {
            throw DraftStoreError.unavailable
        }
    }

    private static func migrate(_ database: OpaquePointer) throws {
        let currentVersion = try schemaVersion(of: database)
        guard currentVersion <= schemaVersion else {
            throw DraftStoreError.newerSchema
        }
        guard currentVersion < schemaVersion else { return }

        do {
            try execute(database, sql: "BEGIN IMMEDIATE;")
            if currentVersion == 0 {
                try execute(database, sql: """
                CREATE TABLE drafts (
                    id TEXT PRIMARY KEY NOT NULL,
                    created_at REAL NOT NULL,
                    updated_at REAL NOT NULL,
                    event_start REAL,
                    normalized_title TEXT NOT NULL,
                    normalized_location TEXT NOT NULL,
                    source_fingerprint TEXT,
                    lifecycle TEXT NOT NULL CHECK (lifecycle IN ('draft', 'created')),
                    payload_version INTEGER NOT NULL,
                    payload BLOB NOT NULL
                );
                """)
                try execute(
                    database,
                    sql: "CREATE INDEX drafts_updated_at_idx ON drafts(updated_at DESC);"
                )
                try execute(
                    database,
                    sql: "CREATE INDEX drafts_duplicate_idx ON drafts(normalized_title, event_start, normalized_location);"
                )
            } else if currentVersion == 1 {
                try execute(
                    database,
                    sql: "ALTER TABLE drafts ADD COLUMN source_fingerprint TEXT;"
                )
            }
            try execute(
                database,
                sql: "CREATE INDEX drafts_fingerprint_idx ON drafts(source_fingerprint);"
            )
            try execute(database, sql: "PRAGMA user_version = 2;")
            try execute(database, sql: "COMMIT;")
        } catch {
            try? execute(database, sql: "ROLLBACK;")
            throw DraftStoreError.migrationFailed
        }
    }

    private static func schemaVersion(of database: OpaquePointer) throws -> Int {
        let statement = try prepare(database, sql: "PRAGMA user_version;")
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw DraftStoreError.migrationFailed
        }
        return Int(sqlite3_column_int(statement, 0))
    }

    private static func execute(_ database: OpaquePointer, sql: String) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw DraftStoreError.migrationFailed
        }
    }

    private static func prepare(_ database: OpaquePointer, sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw DraftStoreError.unavailable
        }
        return statement
    }

    private static func bind(_ value: String, to statement: OpaquePointer, at index: Int32) {
        sqlite3_bind_text(statement, index, value, -1, sqliteTransient)
    }

    private static func bind(_ value: String?, to statement: OpaquePointer, at index: Int32) {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }
        bind(value, to: statement, at: index)
    }

    private static func bind(_ value: Double?, to statement: OpaquePointer, at index: Int32) {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }
        sqlite3_bind_double(statement, index, value)
    }

    private static func bind(_ value: Data, to statement: OpaquePointer, at index: Int32) {
        _ = value.withUnsafeBytes { bytes in
            sqlite3_bind_blob(
                statement,
                index,
                bytes.baseAddress,
                Int32(bytes.count),
                sqliteTransient
            )
        }
    }

    private static func data(from statement: OpaquePointer, column: Int32) throws -> Data {
        let count = Int(sqlite3_column_bytes(statement, column))
        guard count > 0, let bytes = sqlite3_column_blob(statement, column) else {
            throw DraftStoreError.invalidRecord
        }
        return Data(bytes: bytes, count: count)
    }

    private static func normalized(_ value: String?) -> String {
        (value ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(
                options: [.diacriticInsensitive, .caseInsensitive],
                locale: Locale(identifier: "vi_VN")
            )
            .lowercased()
    }
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
