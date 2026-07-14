import Foundation
import XCTest
@testable import SnapCal

final class ScreenshotVaultTests: XCTestCase {
    func testUserDefaultsPreferencePersistsOptInAcrossStoreInstances() throws {
        let suiteName = "SnapCalScreenshotVaultTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let first = UserDefaultsPrivacyPreferenceStore(defaults: defaults)
        XCTAssertFalse(first.screenshotHistoryEnabled)
        first.setScreenshotHistoryEnabled(true)

        let relaunched = UserDefaultsPrivacyPreferenceStore(defaults: defaults)
        XCTAssertTrue(relaunched.screenshotHistoryEnabled)
    }

    func testEncryptedRoundTripContainsNoPlaintextAndUsesOwnerOnlyPermissions() async throws {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        let keyStore = TestScreenshotKeyStore()
        let vault = try EncryptedScreenshotVault(
            directoryURL: fixture.directory,
            keyStore: keyStore
        )
        let id = UUID()
        let plaintext = Data("PRIVATE_SCREENSHOT_BYTES_SENTINEL".utf8)

        try await vault.store(plaintext, draftID: id)

        let file = fixture.directory.appendingPathComponent("\(id.uuidString).snapcalimage")
        let encrypted = try Data(contentsOf: file)
        XCTAssertNotEqual(encrypted, plaintext)
        XCTAssertNil(encrypted.range(of: plaintext))
        let restored = try await vault.load(draftID: id)
        XCTAssertEqual(restored, plaintext)
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }

    func testPerDraftDeleteAndClearAllRemoveFilesAndKey() async throws {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        let keyStore = TestScreenshotKeyStore()
        let vault = try EncryptedScreenshotVault(
            directoryURL: fixture.directory,
            keyStore: keyStore
        )
        let first = UUID()
        let second = UUID()
        try await vault.store(Data("first".utf8), draftID: first)
        try await vault.store(Data("second".utf8), draftID: second)

        try await vault.delete(draftID: first)
        let deletedDraft = try await vault.load(draftID: first)
        let retainedDraft = try await vault.load(draftID: second)
        XCTAssertNil(deletedDraft)
        XCTAssertNotNil(retainedDraft)

        try await vault.deleteAll()
        let remaining = try FileManager.default.contentsOfDirectory(
            at: fixture.directory,
            includingPropertiesForKeys: nil
        )
        XCTAssertTrue(remaining.isEmpty)
        let deletedKey = try await keyStore.readKey()
        XCTAssertNil(deletedKey)
    }

    private func makeFixture() -> VaultFixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SnapCalScreenshotVaultTests")
            .appendingPathComponent(UUID().uuidString)
        return VaultFixture(
            root: root,
            directory: root.appendingPathComponent("Screenshots")
        )
    }
}

private actor TestScreenshotKeyStore: ScreenshotKeyStoring {
    private var key: Data?

    func readKey() async throws -> Data? { key }
    func saveKey(_ data: Data) async throws { key = data }
    func deleteKey() async throws { key = nil }
}

private struct VaultFixture {
    let root: URL
    let directory: URL

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }
}
