import Foundation
import XCTest
@testable import SnapCal

final class GoogleOAuthTests: XCTestCase {
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
