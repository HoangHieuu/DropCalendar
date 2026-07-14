import Foundation
import SQLite3
import XCTest
@testable import SnapCal

final class SQLiteDraftStoreTests: XCTestCase {
    func testRoundTripAcrossStoreInstancesPreservesReviewFieldsButNotFullOCR() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let stored = makePersistedDraft(updatedAt: Date(timeIntervalSince1970: 100))

        let firstStore = try SQLiteDraftStore(databaseURL: fixture.databaseURL)
        try await firstStore.save(stored)
        let secondStore = try SQLiteDraftStore(databaseURL: fixture.databaseURL)
        let loadedValue = try await secondStore.load(id: stored.id)
        let loaded = try XCTUnwrap(loadedValue)
        let restored = try loaded.restore()

        XCTAssertEqual(loaded, stored)
        XCTAssertEqual(restored.0.id, stored.id)
        XCTAssertEqual(restored.0.title.value, "Hội thảo AI")
        XCTAssertEqual(restored.0.title.evidenceText, "HỘI THẢO AI")
        XCTAssertEqual(restored.0.location.value, "Đại học Bách Khoa")
        XCTAssertEqual(restored.0.rawOCRText, "")
        XCTAssertEqual(restored.1, .openRouter(model: "test/model"))
    }

    func testRecentOrderingUpdateAndExplicitDeletion() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let store = try SQLiteDraftStore(databaseURL: fixture.databaseURL)
        let older = makePersistedDraft(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            updatedAt: Date(timeIntervalSince1970: 100),
            title: "Older"
        )
        var newer = makePersistedDraft(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            updatedAt: Date(timeIntervalSince1970: 200),
            title: "Newer"
        )

        try await store.save(older)
        try await store.save(newer)
        var recent = try await store.recent(limit: 20)
        XCTAssertEqual(recent.map(\.id), [newer.id, older.id])

        newer = makePersistedDraft(
            id: newer.id,
            updatedAt: Date(timeIntervalSince1970: 300),
            title: "Updated"
        )
        try await store.save(newer)
        recent = try await store.recent(limit: 20)
        XCTAssertEqual(recent.count, 2)
        XCTAssertEqual(recent.first?.title, "Updated")

        try await store.delete(id: newer.id)
        let deletedDraft = try await store.load(id: newer.id)
        let retainedDraft = try await store.load(id: older.id)
        XCTAssertNil(deletedDraft)
        XCTAssertNotNil(retainedDraft)
    }

    func testDatabaseUsesOwnerOnlyPermissionsAndExcludesSensitiveInput() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let store = try SQLiteDraftStore(databaseURL: fixture.databaseURL)
        try await store.save(makePersistedDraft())

        let databaseAttributes = try FileManager.default.attributesOfItem(
            atPath: fixture.databaseURL.path
        )
        let directoryAttributes = try FileManager.default.attributesOfItem(
            atPath: fixture.databaseURL.deletingLastPathComponent().path
        )
        XCTAssertEqual((databaseAttributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        XCTAssertEqual((directoryAttributes[.posixPermissions] as? NSNumber)?.intValue, 0o700)

        let files = try FileManager.default.contentsOfDirectory(
            at: fixture.databaseURL.deletingLastPathComponent(),
            includingPropertiesForKeys: nil
        )
        let storedBytes = try files.reduce(into: Data()) { result, url in
            result.append(try Data(contentsOf: url))
        }
        XCTAssertNil(String(data: storedBytes, encoding: .utf8)?.range(
            of: "SENSITIVE_FULL_OCR_SENTINEL"
        ))
        XCTAssertNil(String(data: storedBytes, encoding: .utf8)?.range(
            of: "PRIVATE_SCREENSHOT_BYTES_SENTINEL"
        ))
    }

    func testRejectsDatabaseFromNewerSchema() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        try FileManager.default.createDirectory(
            at: fixture.root,
            withIntermediateDirectories: true
        )
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(fixture.databaseURL.path, &database), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(database, "PRAGMA user_version = 99;", nil, nil, nil), SQLITE_OK)
        sqlite3_close(database)

        XCTAssertThrowsError(try SQLiteDraftStore(databaseURL: fixture.databaseURL)) { error in
            XCTAssertEqual(error as? DraftStoreError, .newerSchema)
        }
    }

    func testMigratesVersionOneDatabaseBeforeSavingFingerprint() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        try FileManager.default.createDirectory(
            at: fixture.root,
            withIntermediateDirectories: true
        )
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(fixture.databaseURL.path, &database), SQLITE_OK)
        let versionOneSchema = """
        CREATE TABLE drafts (
            id TEXT PRIMARY KEY NOT NULL,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL,
            event_start REAL,
            normalized_title TEXT NOT NULL,
            normalized_location TEXT NOT NULL,
            lifecycle TEXT NOT NULL CHECK (lifecycle IN ('draft', 'created')),
            payload_version INTEGER NOT NULL,
            payload BLOB NOT NULL
        );
        CREATE INDEX drafts_updated_at_idx ON drafts(updated_at DESC);
        CREATE INDEX drafts_duplicate_idx ON drafts(normalized_title, event_start, normalized_location);
        PRAGMA user_version = 1;
        """
        XCTAssertEqual(sqlite3_exec(database, versionOneSchema, nil, nil, nil), SQLITE_OK)
        sqlite3_close(database)

        let store = try SQLiteDraftStore(databaseURL: fixture.databaseURL)
        let stored = makePersistedDraft(sourceFingerprint: "sha256-fixture")
        try await store.save(stored)
        let loaded = try await store.load(id: stored.id)

        XCTAssertEqual(loaded?.sourceFingerprint, "sha256-fixture")
        XCTAssertEqual(try pragmaUserVersion(fixture.databaseURL), 2)
        XCTAssertTrue(try columnNames(fixture.databaseURL).contains("source_fingerprint"))
    }

    func testVersionOnePayloadDefaultsPhaseFourFieldsDuringDecode() throws {
        let original = makePersistedDraft(sourceFingerprint: "sha256-fixture")
        let encoded = try JSONEncoder().encode(original)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object["sourceFingerprint"] = nil
        object["reminders"] = nil
        let legacyPayload = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(PersistedDraft.self, from: legacyPayload)

        XCTAssertNil(decoded.sourceFingerprint)
        XCTAssertTrue(decoded.reminders.isEmpty)
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.title, original.title)
    }

    private func makePersistedDraft(
        id: UUID = UUID(),
        updatedAt: Date = Date(timeIntervalSince1970: 200),
        title: String = "Hội thảo AI",
        sourceFingerprint: String? = nil
    ) -> PersistedDraft {
        let start = Date(timeIntervalSince1970: 1_787_415_400)
        let draft = EventDraft(
            id: id,
            createdAt: Date(timeIntervalSince1970: 50),
            capturedAt: Date(timeIntervalSince1970: 40),
            sourceFileName: "poster.png",
            sourceFingerprint: sourceFingerprint,
            detectedLanguage: .mixed,
            rawOCRText: "SENSITIVE_FULL_OCR_SENTINEL PRIVATE_SCREENSHOT_BYTES_SENTINEL",
            title: ExtractedField(
                value: title,
                evidenceText: "HỘI THẢO AI",
                confidence: 0.91
            ),
            start: ExtractedField(
                value: start,
                evidenceText: "20h ngày 15/8/2026",
                confidence: 0.93
            ),
            end: ExtractedField(
                value: start.addingTimeInterval(7_200),
                evidenceText: nil,
                confidence: 0.6,
                isInferred: true
            ),
            location: ExtractedField(
                value: "Đại học Bách Khoa",
                evidenceText: "ĐH Bách Khoa",
                confidence: 0.88
            ),
            description: ExtractedField(
                value: "Vietnamese-English workshop",
                evidenceText: "Workshop",
                confidence: 0.8
            ),
            ambiguities: [
                DraftAmbiguity(
                    field: .endTime,
                    message: "End time was inferred.",
                    severity: .medium
                )
            ]
        )
        return PersistedDraft(
            draft: draft,
            updatedAt: updatedAt,
            extractionNotice: .openRouter(model: "test/model"),
            lifecycle: .draft,
            receipt: nil
        )
    }

    private func makeFixture() throws -> Fixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SnapCalSQLiteDraftStoreTests")
            .appendingPathComponent(UUID().uuidString)
        return Fixture(
            root: root,
            databaseURL: root.appendingPathComponent("drafts.sqlite3")
        )
    }

    private func pragmaUserVersion(_ databaseURL: URL) throws -> Int {
        var database: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let database else {
            throw DraftStoreError.unavailable
        }
        defer { sqlite3_close(database) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "PRAGMA user_version;", -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw DraftStoreError.unavailable
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw DraftStoreError.unavailable }
        return Int(sqlite3_column_int(statement, 0))
    }

    private func columnNames(_ databaseURL: URL) throws -> [String] {
        var database: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let database else {
            throw DraftStoreError.unavailable
        }
        defer { sqlite3_close(database) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "PRAGMA table_info(drafts);", -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw DraftStoreError.unavailable
        }
        defer { sqlite3_finalize(statement) }
        var names: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let bytes = sqlite3_column_text(statement, 1) else { continue }
            names.append(String(cString: bytes))
        }
        return names
    }
}

private struct Fixture {
    let root: URL
    let databaseURL: URL

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }
}
