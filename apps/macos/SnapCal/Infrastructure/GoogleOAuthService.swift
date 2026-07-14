import AppKit
import CryptoKit
import Foundation
import Security

struct GoogleOAuthConfiguration: Sendable {
    let clientID: String
    let authorizationEndpoint: URL
    let tokenBrokerEndpoint: URL
    let scope: String

    static let live = GoogleOAuthConfiguration(
        clientID: "837353414684-80cr1usgvcr0p85u908d3q51uml9ul5u.apps.googleusercontent.com",
        authorizationEndpoint: URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!,
        tokenBrokerEndpoint: URL(string: "http://127.0.0.1:8765/v1/google-oauth/token")!,
        scope: "https://www.googleapis.com/auth/calendar.events.owned"
    )
}

struct OAuthAccessToken: Equatable, Sendable {
    let value: String
    let expiresAt: Date

    func isUsable(at date: Date = Date()) -> Bool {
        expiresAt.timeIntervalSince(date) > 60
    }
}

struct OAuthTokenResponse: Decodable, Equatable, Sendable {
    let accessToken: String
    let expiresIn: Double
    let refreshToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
    }
}

enum OAuthSecurity {
    static func randomURLSafeString(byteCount: Int = 32) throws -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw GoogleCalendarError.invalidConfiguration
        }
        return base64URL(Data(bytes))
    }

    static func codeChallenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

enum OAuthCallbackParser {
    static func authorizationCode(from url: URL, expectedState: String) throws -> String {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw GoogleCalendarError.invalidAuthorizationResponse
        }
        let queryItems = components.queryItems ?? []
        func singleValue(named name: String) -> String? {
            let matches = queryItems.filter { $0.name == name }
            guard matches.count == 1 else { return nil }
            return matches[0].value ?? ""
        }
        guard singleValue(named: "state") == expectedState else {
            throw GoogleCalendarError.stateMismatch
        }
        if singleValue(named: "error") == "access_denied" {
            throw GoogleCalendarError.authorizationDenied
        }
        guard let code = singleValue(named: "code"), !code.isEmpty else {
            throw GoogleCalendarError.invalidAuthorizationResponse
        }
        return code
    }
}

actor GoogleOAuthService {
    private struct TokenBrokerRequest: Encodable {
        let clientID: String
        let grantType: String
        let code: String?
        let codeVerifier: String?
        let redirectURI: String?
        let refreshToken: String?

        enum CodingKeys: String, CodingKey {
            case clientID = "client_id"
            case grantType = "grant_type"
            case code
            case codeVerifier = "code_verifier"
            case redirectURI = "redirect_uri"
            case refreshToken = "refresh_token"
        }
    }

    private struct TokenBrokerErrorResponse: Decodable {
        struct Detail: Decodable {
            let code: String
        }

        let detail: Detail
    }

    private let configuration: GoogleOAuthConfiguration
    private let credentialStore: any OAuthCredentialStoring
    private let transport: any HTTPTransport
    private var accessToken: OAuthAccessToken?

    init(
        configuration: GoogleOAuthConfiguration,
        credentialStore: any OAuthCredentialStoring,
        transport: any HTTPTransport = URLSessionHTTPTransport()
    ) {
        self.configuration = configuration
        self.credentialStore = credentialStore
        self.transport = transport
    }

    func hasStoredAuthorization() async -> Bool {
        (try? await credentialStore.readRefreshToken()) != nil
    }

    func validAccessToken() async throws -> String {
        if let accessToken, accessToken.isUsable() {
            return accessToken.value
        }
        if let refreshToken = try await credentialStore.readRefreshToken() {
            do {
                return try await refreshAccessToken(using: refreshToken)
            } catch GoogleCalendarError.tokenExchangeFailed {
                try? await credentialStore.deleteRefreshToken()
                accessToken = nil
            } catch {
                throw error
            }
        }
        return try await authorizeInteractively()
    }

    func disconnect() async throws {
        accessToken = nil
        try await credentialStore.deleteRefreshToken()
    }

    private func authorizeInteractively() async throws -> String {
        let callbackServer = try LoopbackOAuthServer()
        let redirectURI = try await callbackServer.start()
        let verifier = try OAuthSecurity.randomURLSafeString(byteCount: 48)
        let state = try OAuthSecurity.randomURLSafeString()
        let authorizationURL = try makeAuthorizationURL(
            redirectURI: redirectURI,
            verifier: verifier,
            state: state
        )

        let didOpen = await MainActor.run {
            NSWorkspace.shared.open(authorizationURL)
        }
        guard didOpen else {
            callbackServer.cancel()
            throw GoogleCalendarError.callbackFailed
        }

        let callbackURL = try await waitForCallback(from: callbackServer)
        let code = try OAuthCallbackParser.authorizationCode(from: callbackURL, expectedState: state)
        let tokenResponse = try await exchangeAuthorizationCode(
            code,
            verifier: verifier,
            redirectURI: redirectURI
        )
        return await acceptInteractiveTokenResponse(tokenResponse)
    }

    private func waitForCallback(from server: LoopbackOAuthServer) async throws -> URL {
        try await withThrowingTaskGroup(of: URL.self) { group in
            group.addTask {
                try await server.waitForCallback()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: 180_000_000_000)
                throw GoogleCalendarError.authorizationTimedOut
            }
            defer { group.cancelAll() }
            guard let callbackURL = try await group.next() else {
                throw GoogleCalendarError.callbackFailed
            }
            return callbackURL
        }
    }

    private func refreshAccessToken(using refreshToken: String) async throws -> String {
        let tokenResponse = try await performTokenRequest(TokenBrokerRequest(
            clientID: configuration.clientID,
            grantType: "refresh_token",
            code: nil,
            codeVerifier: nil,
            redirectURI: nil,
            refreshToken: refreshToken
        ))
        return cache(tokenResponse)
    }

    private func exchangeAuthorizationCode(
        _ code: String,
        verifier: String,
        redirectURI: URL
    ) async throws -> OAuthTokenResponse {
        try await performTokenRequest(TokenBrokerRequest(
            clientID: configuration.clientID,
            grantType: "authorization_code",
            code: code,
            codeVerifier: verifier,
            redirectURI: redirectURI.absoluteString,
            refreshToken: nil
        ))
    }

    private func performTokenRequest(_ payload: TokenBrokerRequest) async throws -> OAuthTokenResponse {
        var request = URLRequest(url: configuration.tokenBrokerEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.data(for: request)
        } catch {
            throw GoogleCalendarError.oauthBrokerUnavailable
        }

        guard response.statusCode == 200 else {
            let code = try? JSONDecoder().decode(TokenBrokerErrorResponse.self, from: data).detail.code
            if code == "oauth_client_mismatch" {
                throw GoogleCalendarError.oauthCredentialMismatch
            }
            if response.statusCode == 503 || code == "oauth_broker_unavailable" {
                throw GoogleCalendarError.oauthBrokerUnavailable
            }
            throw GoogleCalendarError.tokenExchangeFailed
        }
        guard let decoded = try? JSONDecoder().decode(OAuthTokenResponse.self, from: data),
              !decoded.accessToken.isEmpty,
              decoded.expiresIn > 0 else {
            throw GoogleCalendarError.tokenExchangeFailed
        }
        return decoded
    }

    func acceptInteractiveTokenResponse(_ response: OAuthTokenResponse) async -> String {
        let token = cache(response)
        if let refreshToken = response.refreshToken, !refreshToken.isEmpty {
            try? await credentialStore.saveRefreshToken(refreshToken)
        }
        return token
    }

    private func cache(_ response: OAuthTokenResponse) -> String {
        let token = OAuthAccessToken(
            value: response.accessToken,
            expiresAt: Date().addingTimeInterval(response.expiresIn)
        )
        accessToken = token
        return token.value
    }

    private func makeAuthorizationURL(
        redirectURI: URL,
        verifier: String,
        state: String
    ) throws -> URL {
        guard var components = URLComponents(
            url: configuration.authorizationEndpoint,
            resolvingAgainstBaseURL: false
        ) else {
            throw GoogleCalendarError.invalidConfiguration
        }
        components.queryItems = [
            URLQueryItem(name: "client_id", value: configuration.clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI.absoluteString),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: configuration.scope),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
            URLQueryItem(name: "code_challenge", value: OAuthSecurity.codeChallenge(for: verifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state)
        ]
        guard let url = components.url else {
            throw GoogleCalendarError.invalidConfiguration
        }
        return url
    }

}
