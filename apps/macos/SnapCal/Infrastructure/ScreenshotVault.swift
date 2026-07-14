import CryptoKit
import Foundation
import Security

protocol ScreenshotKeyStoring: Sendable {
    func readKey() async throws -> Data?
    func saveKey(_ data: Data) async throws
    func deleteKey() async throws
}

enum ScreenshotVaultError: LocalizedError, Equatable {
    case unavailable
    case encryptionFailed
    case invalidCiphertext
    case keychainFailed

    var errorDescription: String? {
        switch self {
        case .keychainFailed:
            return "Encrypted screenshot history could not access its Keychain key."
        case .unavailable, .encryptionFailed, .invalidCiphertext:
            return "Encrypted screenshot history is temporarily unavailable."
        }
    }
}

struct KeychainScreenshotKeyStore: ScreenshotKeyStoring {
    private let service = "com.snapcal.app.screenshot-vault"
    private let account = "vault-key-v1"
    private let preferredBackend: KeychainStorageBackend

    init(preferredBackend: KeychainStorageBackend? = nil) {
        self.preferredBackend = preferredBackend ?? KeychainStoragePolicy.preferredBackend(
            teamIdentifier: KeychainStoragePolicy.currentTeamIdentifier()
        )
    }

    func readKey() async throws -> Data? {
        for backend in orderedBackends {
            var query = baseQuery(backend: backend)
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            var result: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            if status == errSecItemNotFound || backendUnavailable(status) { continue }
            guard status == errSecSuccess, let data = result as? Data, data.count == 32 else {
                throw ScreenshotVaultError.keychainFailed
            }
            return data
        }
        return nil
    }

    func saveKey(_ data: Data) async throws {
        guard data.count == 32 else { throw ScreenshotVaultError.keychainFailed }
        let query = baseQuery(backend: preferredBackend)
        var status = SecItemUpdate(
            query as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrLabel as String] = "SnapCal encrypted screenshot history key"
            if preferredBackend == .dataProtection {
                item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            }
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw ScreenshotVaultError.keychainFailed }
        _ = SecItemDelete(baseQuery(backend: alternateBackend) as CFDictionary)
    }

    func deleteKey() async throws {
        for backend in orderedBackends {
            let status = SecItemDelete(baseQuery(backend: backend) as CFDictionary)
            guard status == errSecSuccess
                    || status == errSecItemNotFound
                    || backendUnavailable(status) else {
                throw ScreenshotVaultError.keychainFailed
            }
        }
    }

    private var orderedBackends: [KeychainStorageBackend] {
        [preferredBackend, alternateBackend]
    }

    private var alternateBackend: KeychainStorageBackend {
        preferredBackend == .dataProtection ? .login : .dataProtection
    }

    private func backendUnavailable(_ status: OSStatus) -> Bool {
        status == errSecMissingEntitlement || status == errSecNotAvailable
    }

    private func baseQuery(backend: KeychainStorageBackend) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        if backend == .dataProtection {
            query[kSecUseDataProtectionKeychain as String] = true
        }
        return query
    }
}

protocol ScreenshotVaulting: Sendable {
    func store(_ imageData: Data, draftID: UUID) async throws
    func load(draftID: UUID) async throws -> Data?
    func delete(draftID: UUID) async throws
    func deleteAll() async throws
}

struct DisabledScreenshotVault: ScreenshotVaulting {
    func store(_ imageData: Data, draftID: UUID) async throws { }
    func load(draftID: UUID) async throws -> Data? { nil }
    func delete(draftID: UUID) async throws { }
    func deleteAll() async throws { }
}

struct UnavailableScreenshotVault: ScreenshotVaulting {
    func store(_ imageData: Data, draftID: UUID) async throws { throw ScreenshotVaultError.unavailable }
    func load(draftID: UUID) async throws -> Data? { throw ScreenshotVaultError.unavailable }
    func delete(draftID: UUID) async throws { throw ScreenshotVaultError.unavailable }
    func deleteAll() async throws { throw ScreenshotVaultError.unavailable }
}

actor EncryptedScreenshotVault: ScreenshotVaulting {
    private let directoryURL: URL
    private let keyStore: any ScreenshotKeyStoring

    init(directoryURL: URL, keyStore: any ScreenshotKeyStoring) throws {
        self.directoryURL = directoryURL
        self.keyStore = keyStore
        try Self.prepareDirectory(directoryURL)
    }

    static func live() throws -> EncryptedScreenshotVault {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return try EncryptedScreenshotVault(
            directoryURL: support
                .appendingPathComponent("SnapCal", isDirectory: true)
                .appendingPathComponent("Screenshots", isDirectory: true),
            keyStore: KeychainScreenshotKeyStore()
        )
    }

    func store(_ imageData: Data, draftID: UUID) async throws {
        guard !imageData.isEmpty else { throw ScreenshotVaultError.encryptionFailed }
        try Self.prepareDirectory(directoryURL)
        let key = try await encryptionKey()
        let sealed: AES.GCM.SealedBox
        do {
            sealed = try AES.GCM.seal(imageData, using: key)
        } catch {
            throw ScreenshotVaultError.encryptionFailed
        }
        guard let combined = sealed.combined else {
            throw ScreenshotVaultError.encryptionFailed
        }
        let destination = fileURL(for: draftID)
        do {
            try combined.write(to: destination, options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: destination.path
            )
        } catch {
            throw ScreenshotVaultError.unavailable
        }
    }

    func load(draftID: UUID) async throws -> Data? {
        let file = fileURL(for: draftID)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let encrypted: Data
        do {
            encrypted = try Data(contentsOf: file)
        } catch {
            throw ScreenshotVaultError.unavailable
        }
        guard let keyData = try await keyStore.readKey() else {
            throw ScreenshotVaultError.keychainFailed
        }
        do {
            let box = try AES.GCM.SealedBox(combined: encrypted)
            return try AES.GCM.open(box, using: SymmetricKey(data: keyData))
        } catch {
            throw ScreenshotVaultError.invalidCiphertext
        }
    }

    func delete(draftID: UUID) async throws {
        let file = fileURL(for: draftID)
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        do {
            try FileManager.default.removeItem(at: file)
        } catch {
            throw ScreenshotVaultError.unavailable
        }
    }

    func deleteAll() async throws {
        do {
            if FileManager.default.fileExists(atPath: directoryURL.path) {
                try FileManager.default.removeItem(at: directoryURL)
            }
            try Self.prepareDirectory(directoryURL)
            try await keyStore.deleteKey()
        } catch let error as ScreenshotVaultError {
            throw error
        } catch {
            throw ScreenshotVaultError.unavailable
        }
    }

    private func encryptionKey() async throws -> SymmetricKey {
        if let data = try await keyStore.readKey() {
            guard data.count == 32 else { throw ScreenshotVaultError.keychainFailed }
            return SymmetricKey(data: data)
        }
        let key = SymmetricKey(size: .bits256)
        let data = key.withUnsafeBytes { Data($0) }
        try await keyStore.saveKey(data)
        return key
    }

    private func fileURL(for draftID: UUID) -> URL {
        directoryURL.appendingPathComponent("\(draftID.uuidString).snapcalimage")
    }

    private static func prepareDirectory(_ directoryURL: URL) throws {
        do {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: directoryURL.path
            )
        } catch {
            throw ScreenshotVaultError.unavailable
        }
    }
}

protocol PrivacyPreferenceStoring {
    var screenshotHistoryEnabled: Bool { get }
    func setScreenshotHistoryEnabled(_ enabled: Bool)
}

struct UserDefaultsPrivacyPreferenceStore: PrivacyPreferenceStoring {
    private static let key = "privacy.screenshotHistoryEnabled"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var screenshotHistoryEnabled: Bool {
        defaults.bool(forKey: Self.key)
    }

    func setScreenshotHistoryEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Self.key)
    }
}

struct InMemoryPrivacyPreferenceStore: PrivacyPreferenceStoring {
    var screenshotHistoryEnabled = false
    func setScreenshotHistoryEnabled(_ enabled: Bool) { }
}
