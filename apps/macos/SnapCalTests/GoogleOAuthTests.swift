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
            tokenEndpoint: tokenEndpoint,
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
        let body = String(data: try XCTUnwrap(request.httpBody), encoding: .utf8)

        XCTAssertEqual(token, "new-access-token")
        XCTAssertEqual(request.url, tokenEndpoint)
        XCTAssertTrue(body?.contains("refresh_token=stored-refresh-token") == true)
        XCTAssertTrue(body?.contains("client_id=desktop-client-id") == true)
        XCTAssertFalse(body?.contains("client_secret") == true)
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
