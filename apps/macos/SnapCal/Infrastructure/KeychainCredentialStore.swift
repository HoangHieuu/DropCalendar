import Foundation
import Security

protocol OAuthCredentialStoring: Sendable {
    func readRefreshToken() async throws -> String?
    func saveRefreshToken(_ token: String) async throws
    func deleteRefreshToken() async throws
}

struct KeychainCredentialStore: OAuthCredentialStoring {
    private let service: String
    private let account: String

    init(service: String = "com.snapcal.app.google-oauth", account: String) {
        self.service = service
        self.account = account
    }

    func readRefreshToken() async throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8),
              !token.isEmpty else {
            throw GoogleCalendarError.keychainFailure
        }
        return token
    }

    func saveRefreshToken(_ token: String) async throws {
        guard let data = token.data(using: .utf8), !data.isEmpty else {
            throw GoogleCalendarError.keychainFailure
        }

        let status = SecItemUpdate(
            baseQuery as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else {
            throw GoogleCalendarError.keychainFailure
        }

        var item = baseQuery
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw GoogleCalendarError.keychainFailure
        }
    }

    func deleteRefreshToken() async throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw GoogleCalendarError.keychainFailure
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true
        ]
    }
}
