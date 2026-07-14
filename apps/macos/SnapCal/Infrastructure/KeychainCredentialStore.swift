import Foundation
import Security

protocol OAuthCredentialStoring: Sendable {
    func readRefreshToken() async throws -> String?
    func saveRefreshToken(_ token: String) async throws
    func deleteRefreshToken() async throws
}

enum KeychainStorageBackend: Sendable, Equatable, Hashable {
    case dataProtection
    case login
}

enum KeychainReadResult: Sendable, Equatable {
    case value(Data)
    case notFound
    case failed(OSStatus)
}

protocol KeychainItemAccessing: Sendable {
    func read(service: String, account: String, backend: KeychainStorageBackend) -> KeychainReadResult
    func write(
        _ data: Data,
        service: String,
        account: String,
        backend: KeychainStorageBackend
    ) -> OSStatus
    func delete(service: String, account: String, backend: KeychainStorageBackend) -> OSStatus
}

struct KeychainStoragePolicy {
    static func preferredBackend(teamIdentifier: String?) -> KeychainStorageBackend {
        guard let teamIdentifier,
              !teamIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .login
        }
        return .dataProtection
    }

    static func currentTeamIdentifier() -> String? {
        var dynamicCode: SecCode?
        guard SecCodeCopySelf(SecCSFlags(), &dynamicCode) == errSecSuccess,
              let dynamicCode else {
            return nil
        }

        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(dynamicCode, SecCSFlags(), &staticCode) == errSecSuccess,
              let staticCode else {
            return nil
        }

        var signingInformation: CFDictionary?
        guard SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &signingInformation
        ) == errSecSuccess else {
            return nil
        }

        return (signingInformation as NSDictionary?)?[kSecCodeInfoTeamIdentifier] as? String
    }
}

struct KeychainCredentialStore: OAuthCredentialStoring {
    private let service: String
    private let account: String
    private let preferredBackend: KeychainStorageBackend
    private let itemClient: any KeychainItemAccessing

    init(
        service: String = "com.snapcal.app.google-oauth",
        account: String,
        preferredBackend: KeychainStorageBackend? = nil,
        itemClient: any KeychainItemAccessing = SecurityKeychainItemClient()
    ) {
        self.service = service
        self.account = account
        self.preferredBackend = preferredBackend ?? KeychainStoragePolicy.preferredBackend(
            teamIdentifier: KeychainStoragePolicy.currentTeamIdentifier()
        )
        self.itemClient = itemClient
    }

    func readRefreshToken() async throws -> String? {
        for backend in orderedBackends {
            switch itemClient.read(service: service, account: account, backend: backend) {
            case .value(let data):
                guard let token = String(data: data, encoding: .utf8), !token.isEmpty else {
                    throw GoogleCalendarError.keychainFailure
                }
                return token
            case .notFound:
                continue
            case .failed(let status):
                guard Self.backendUnavailable(status) else {
                    throw GoogleCalendarError.keychainFailure
                }
            }
        }
        return nil
    }

    func saveRefreshToken(_ token: String) async throws {
        guard let data = token.data(using: .utf8), !data.isEmpty else {
            throw GoogleCalendarError.keychainFailure
        }

        let status = itemClient.write(
            data,
            service: service,
            account: account,
            backend: preferredBackend
        )
        guard status == errSecSuccess else {
            throw GoogleCalendarError.keychainFailure
        }

        // A signing transition can leave a copy in the alternate store. The
        // preferred write is already durable, so alternate cleanup is best-effort.
        _ = itemClient.delete(
            service: service,
            account: account,
            backend: alternateBackend
        )
    }

    func deleteRefreshToken() async throws {
        var firstFailure: OSStatus?
        for backend in orderedBackends {
            let status = itemClient.delete(service: service, account: account, backend: backend)
            guard status == errSecSuccess || status == errSecItemNotFound || Self.backendUnavailable(status) else {
                firstFailure = firstFailure ?? status
                continue
            }
        }
        if firstFailure != nil {
            throw GoogleCalendarError.keychainFailure
        }
    }

    private var orderedBackends: [KeychainStorageBackend] {
        [preferredBackend, alternateBackend]
    }

    private var alternateBackend: KeychainStorageBackend {
        preferredBackend == .dataProtection ? .login : .dataProtection
    }

    private static func backendUnavailable(_ status: OSStatus) -> Bool {
        status == errSecMissingEntitlement || status == errSecNotAvailable
    }
}

struct SecurityKeychainItemClient: KeychainItemAccessing {
    func read(
        service: String,
        account: String,
        backend: KeychainStorageBackend
    ) -> KeychainReadResult {
        var query = baseQuery(service: service, account: account, backend: backend)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return .notFound }
        guard status == errSecSuccess, let data = result as? Data else {
            return .failed(status)
        }
        return .value(data)
    }

    func write(
        _ data: Data,
        service: String,
        account: String,
        backend: KeychainStorageBackend
    ) -> OSStatus {
        let query = baseQuery(service: service, account: account, backend: backend)
        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess { return errSecSuccess }
        guard updateStatus == errSecItemNotFound else { return updateStatus }

        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrLabel as String] = "SnapCal Google Calendar authorization"
        if backend == .dataProtection {
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        }
        return SecItemAdd(item as CFDictionary, nil)
    }

    func delete(
        service: String,
        account: String,
        backend: KeychainStorageBackend
    ) -> OSStatus {
        SecItemDelete(baseQuery(service: service, account: account, backend: backend) as CFDictionary)
    }

    private func baseQuery(
        service: String,
        account: String,
        backend: KeychainStorageBackend
    ) -> [String: Any] {
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
