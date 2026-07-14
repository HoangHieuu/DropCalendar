import Foundation
import XCTest
@testable import SnapCal

final class GoogleOAuthTests: XCTestCase {
    func testKeychainStoragePolicyUsesLoginForAdHocAndDataProtectionForTeamSignedBuilds() {
        XCTAssertEqual(
            KeychainStoragePolicy.preferredBackend(teamIdentifier: nil),
            .login
        )
        XCTAssertEqual(
            KeychainStoragePolicy.preferredBackend(teamIdentifier: ""),
            .login
        )
        XCTAssertEqual(
            KeychainStoragePolicy.preferredBackend(teamIdentifier: "TEAM123"),
            .dataProtection
        )
    }

    func testCredentialStoreReadsAlternateBackendAcrossSigningTransition() async throws {
        let client = StubKeychainItemClient(readResults: [
            .dataProtection: .notFound,
            .login: .value(Data("persisted-refresh-token".utf8))
        ])
        let store = KeychainCredentialStore(
            service: "com.snapcal.tests.oauth",
            account: "desktop-client-id",
            preferredBackend: .dataProtection,
            itemClient: client
        )

        let token = try await store.readRefreshToken()

        XCTAssertEqual(token, "persisted-refresh-token")
        XCTAssertEqual(client.readBackends(), [.dataProtection, .login])
    }

    func testCredentialStoreWritesOnlyPreferredBackendAndRemovesAlternateCopy() async throws {
        let client = StubKeychainItemClient()
        let store = KeychainCredentialStore(
            service: "com.snapcal.tests.oauth",
            account: "desktop-client-id",
            preferredBackend: .login,
            itemClient: client
        )

        try await store.saveRefreshToken("fixture-refresh-token")

        XCTAssertEqual(client.writeBackends(), [.login])
        XCTAssertEqual(client.deleteBackends(), [.dataProtection])
    }

    func testAdHocLoginKeychainRoundTripUsesIsolatedItemAndCleansUp() async throws {
        let service = "com.snapcal.tests.oauth.\(UUID().uuidString)"
        let store = KeychainCredentialStore(
            service: service,
            account: "isolated-platform-fixture",
            preferredBackend: .login
        )

        try? await store.deleteRefreshToken()
        do {
            try await store.saveRefreshToken("not-a-real-provider-token")
            let savedToken = try await store.readRefreshToken()
            XCTAssertEqual(savedToken, "not-a-real-provider-token")
            try await store.deleteRefreshToken()
            let deletedToken = try await store.readRefreshToken()
            XCTAssertNil(deletedToken)
        } catch {
            try? await store.deleteRefreshToken()
            throw error
        }
    }

    func testTeamSignedDataProtectionKeychainRoundTripUsesIsolatedItemAndCleansUp() async throws {
        guard let teamIdentifier = KeychainStoragePolicy.currentTeamIdentifier() else {
            throw XCTSkip("Data Protection Keychain proof requires a team-signed test host.")
        }
        XCTAssertEqual(
            KeychainStoragePolicy.preferredBackend(teamIdentifier: teamIdentifier),
            .dataProtection
        )

        let service = "com.snapcal.tests.oauth.dataprotection.\(UUID().uuidString)"
        let account = "isolated-platform-fixture"
        let client = SecurityKeychainItemClient()
        let fixture = Data("not-a-real-provider-token".utf8)

        _ = client.delete(service: service, account: account, backend: .dataProtection)
        let writeStatus = client.write(
            fixture,
            service: service,
            account: account,
            backend: .dataProtection
        )
        XCTAssertEqual(writeStatus, errSecSuccess, "Data Protection write OSStatus: \(writeStatus)")
        guard writeStatus == errSecSuccess else { return }

        XCTAssertEqual(
            client.read(service: service, account: account, backend: .dataProtection),
            .value(fixture)
        )
        XCTAssertEqual(
            client.delete(service: service, account: account, backend: .dataProtection),
            errSecSuccess
        )
        XCTAssertEqual(
            client.read(service: service, account: account, backend: .dataProtection),
            .notFound
        )
    }

    func testPKCEChallengeMatchesRFC7636Vector() {
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        XCTAssertEqual(
            OAuthSecurity.codeChallenge(for: verifier),
            "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
        )
    }

    func testCallbackParserRequiresMatchingState() throws {
        let url = try XCTUnwrap(URL(string: "http://127.0.0.1:49152/?code=abc123&state=expected"))
        XCTAssertEqual(
            try OAuthCallbackParser.authorizationCode(from: url, expectedState: "expected"),
            "abc123"
        )

        XCTAssertThrowsError(
            try OAuthCallbackParser.authorizationCode(from: url, expectedState: "different")
        ) { error in
            XCTAssertEqual(error as? GoogleCalendarError, .stateMismatch)
        }
    }

    func testCallbackParserMapsAccessDenied() throws {
        let url = try XCTUnwrap(URL(string: "http://127.0.0.1:49152/?error=access_denied&state=expected"))
        XCTAssertThrowsError(
            try OAuthCallbackParser.authorizationCode(from: url, expectedState: "expected")
        ) { error in
            XCTAssertEqual(error as? GoogleCalendarError, .authorizationDenied)
        }
    }

    func testCallbackParserRejectsDuplicateSecurityParameters() throws {
        let duplicateState = try XCTUnwrap(URL(string: "http://127.0.0.1:49152/?code=abc&state=expected&state=expected"))
        XCTAssertThrowsError(
            try OAuthCallbackParser.authorizationCode(from: duplicateState, expectedState: "expected")
        ) { error in
            XCTAssertEqual(error as? GoogleCalendarError, .stateMismatch)
        }

        let duplicateCode = try XCTUnwrap(URL(string: "http://127.0.0.1:49152/?code=abc&code=def&state=expected"))
        XCTAssertThrowsError(
            try OAuthCallbackParser.authorizationCode(from: duplicateCode, expectedState: "expected")
        ) { error in
            XCTAssertEqual(error as? GoogleCalendarError, .invalidAuthorizationResponse)
        }
    }

    func testStoredRefreshTokenObtainsAccessTokenWithoutClientSecret() async throws {
        let tokenEndpoint = URL(string: "https://oauth.example.test/token")!
        let configuration = GoogleOAuthConfiguration(
            clientID: "desktop-client-id",
            authorizationEndpoint: URL(string: "https://accounts.example.test/auth")!,
            tokenBrokerEndpoint: tokenEndpoint,
            scope: "calendar.events.owned"
        )
        let store = InMemoryCredentialStore(refreshToken: "stored-refresh-token")
        let response = try XCTUnwrap(HTTPURLResponse(
            url: tokenEndpoint,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        ))
        let transport = OAuthRecordingTransport(
            data: Data(#"{"access_token":"new-access-token","expires_in":3600}"#.utf8),
            response: response
        )
        let service = GoogleOAuthService(
            configuration: configuration,
            credentialStore: store,
            transport: transport
        )

        let token = try await service.validAccessToken()
        let recordedRequest = await transport.capturedRequest()
        let request = try XCTUnwrap(recordedRequest)
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: body) as? [String: Any]
        )

        XCTAssertEqual(token, "new-access-token")
        XCTAssertEqual(request.url, tokenEndpoint)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json; charset=utf-8")
        XCTAssertEqual(json["refresh_token"] as? String, "stored-refresh-token")
        XCTAssertEqual(json["client_id"] as? String, "desktop-client-id")
        XCTAssertNil(json["client_secret"])
    }

    func testInteractiveAccessTokenSurvivesRefreshTokenPersistenceFailure() async {
        let tokenEndpoint = URL(string: "http://127.0.0.1:8765/v1/google-oauth/token")!
        let service = GoogleOAuthService(
            configuration: GoogleOAuthConfiguration(
                clientID: "desktop-client-id",
                authorizationEndpoint: URL(string: "https://accounts.example.test/auth")!,
                tokenBrokerEndpoint: tokenEndpoint,
                scope: "calendar.events.owned"
            ),
            credentialStore: FailingSaveCredentialStore()
        )

        let token = await service.acceptInteractiveTokenResponse(OAuthTokenResponse(
            accessToken: "current-access-token",
            expiresIn: 3_600,
            refreshToken: "refresh-token-that-cannot-be-saved"
        ))

        XCTAssertEqual(token, "current-access-token")
        let hasStoredAuthorization = await service.hasStoredAuthorization()
        XCTAssertFalse(hasStoredAuthorization)
    }

    func testUnavailableBrokerPreservesStoredRefreshToken() async throws {
        let tokenEndpoint = URL(string: "http://127.0.0.1:8765/v1/google-oauth/token")!
        let store = InMemoryCredentialStore(refreshToken: "stored-refresh-token")
        let response = try XCTUnwrap(HTTPURLResponse(
            url: tokenEndpoint,
            statusCode: 503,
            httpVersion: nil,
            headerFields: nil
        ))
        let transport = OAuthRecordingTransport(
            data: Data(#"{"detail":{"code":"oauth_broker_unavailable"}}"#.utf8),
            response: response
        )
        let service = GoogleOAuthService(
            configuration: GoogleOAuthConfiguration(
                clientID: "desktop-client-id",
                authorizationEndpoint: URL(string: "https://accounts.example.test/auth")!,
                tokenBrokerEndpoint: tokenEndpoint,
                scope: "calendar.events.owned"
            ),
            credentialStore: store,
            transport: transport
        )

        do {
            _ = try await service.validAccessToken()
            XCTFail("Expected an unavailable broker error")
        } catch {
            XCTAssertEqual(error as? GoogleCalendarError, .oauthBrokerUnavailable)
        }
        let refreshToken = try await store.readRefreshToken()
        XCTAssertEqual(refreshToken, "stored-refresh-token")
    }
}

private actor InMemoryCredentialStore: OAuthCredentialStoring {
    private var refreshToken: String?

    init(refreshToken: String?) {
        self.refreshToken = refreshToken
    }

    func readRefreshToken() async throws -> String? { refreshToken }
    func saveRefreshToken(_ token: String) async throws { refreshToken = token }
    func deleteRefreshToken() async throws { refreshToken = nil }
}

private actor OAuthRecordingTransport: HTTPTransport {
    private let data: Data
    private let response: HTTPURLResponse
    private var request: URLRequest?

    init(data: Data, response: HTTPURLResponse) {
        self.data = data
        self.response = response
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        self.request = request
        return (data, response)
    }

    func capturedRequest() -> URLRequest? { request }
}

private actor FailingSaveCredentialStore: OAuthCredentialStoring {
    func readRefreshToken() async throws -> String? { nil }
    func saveRefreshToken(_ token: String) async throws {
        throw GoogleCalendarError.keychainFailure
    }
    func deleteRefreshToken() async throws { }
}

private final class StubKeychainItemClient: KeychainItemAccessing, @unchecked Sendable {
    private let lock = NSLock()
    private let readResults: [KeychainStorageBackend: KeychainReadResult]
    private let writeStatus: OSStatus
    private let deleteStatus: OSStatus
    private var recordedReads: [KeychainStorageBackend] = []
    private var recordedWrites: [KeychainStorageBackend] = []
    private var recordedDeletes: [KeychainStorageBackend] = []

    init(
        readResults: [KeychainStorageBackend: KeychainReadResult] = [:],
        writeStatus: OSStatus = errSecSuccess,
        deleteStatus: OSStatus = errSecSuccess
    ) {
        self.readResults = readResults
        self.writeStatus = writeStatus
        self.deleteStatus = deleteStatus
    }

    func read(
        service: String,
        account: String,
        backend: KeychainStorageBackend
    ) -> KeychainReadResult {
        lock.lock()
        defer { lock.unlock() }
        recordedReads.append(backend)
        return readResults[backend] ?? .notFound
    }

    func write(
        _ data: Data,
        service: String,
        account: String,
        backend: KeychainStorageBackend
    ) -> OSStatus {
        lock.lock()
        defer { lock.unlock() }
        recordedWrites.append(backend)
        return writeStatus
    }

    func delete(
        service: String,
        account: String,
        backend: KeychainStorageBackend
    ) -> OSStatus {
        lock.lock()
        defer { lock.unlock() }
        recordedDeletes.append(backend)
        return deleteStatus
    }

    func readBackends() -> [KeychainStorageBackend] {
        lock.lock()
        defer { lock.unlock() }
        return recordedReads
    }

    func writeBackends() -> [KeychainStorageBackend] {
        lock.lock()
        defer { lock.unlock() }
        return recordedWrites
    }

    func deleteBackends() -> [KeychainStorageBackend] {
        lock.lock()
        defer { lock.unlock() }
        return recordedDeletes
    }
}
