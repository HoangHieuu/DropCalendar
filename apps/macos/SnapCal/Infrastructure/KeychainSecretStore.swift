import Foundation
import Security

struct KeychainSecretStore: Sendable {
    private let service: String
    private let account: String
    private let preferredBackend: KeychainStorageBackend
    private let itemClient: any KeychainItemAccessing

    init(
        service: String,
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

    func read() throws -> Data? {
        for backend in orderedBackends {
            switch itemClient.read(service: service, account: account, backend: backend) {
            case .value(let value):
                return value
            case .notFound:
                continue
            case .failed(let status):
                guard backendUnavailable(status) else {
                    throw SnapCalAccountError.secureStorage
                }
            }
        }
        return nil
    }

    func write(_ value: Data) throws {
        guard !value.isEmpty else { throw SnapCalAccountError.secureStorage }
        let status = itemClient.write(
            value,
            service: service,
            account: account,
            backend: preferredBackend
        )
        guard status == errSecSuccess else {
            throw SnapCalAccountError.secureStorage
        }
        _ = itemClient.delete(
            service: service,
            account: account,
            backend: alternateBackend
        )
    }

    func delete() throws {
        var failed = false
        for backend in orderedBackends {
            let status = itemClient.delete(service: service, account: account, backend: backend)
            if status != errSecSuccess,
               status != errSecItemNotFound,
               !backendUnavailable(status) {
                failed = true
            }
        }
        if failed { throw SnapCalAccountError.secureStorage }
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
}

