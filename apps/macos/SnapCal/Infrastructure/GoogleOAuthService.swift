import AppKit
import CryptoKit
import Foundation
import Security

struct GoogleOAuthConfiguration: Sendable {
    let clientID: String
    let authorizationEndpoint: URL
    let tokenEndpoint: URL
    let scope: String

    static let live = GoogleOAuthConfiguration(
        clientID: "837353414684-80cr1usgvcr0p85u908d3q51uml9ul5u.apps.googleusercontent.com",
        authorizationEndpoint: URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!,
        tokenEndpoint: URL(string: "https://oauth2.googleapis.com/token")!,
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
    private struct TokenResponse: Decodable {
        let accessToken: String
        let expiresIn: Double
        let refreshToken: String?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case expiresIn = "expires_in"
            case refreshToken = "refresh_token"
        }
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
            } catch {
                try? await credentialStore.deleteRefreshToken()
                accessToken = nil
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
        if let refreshToken = tokenResponse.refreshToken, !refreshToken.isEmpty {
            try await credentialStore.saveRefreshToken(refreshToken)
        } else if try await credentialStore.readRefreshToken() == nil {
            throw GoogleCalendarError.tokenExchangeFailed
        }
        return cache(tokenResponse)
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
        let request = try tokenRequest(parameters: [
            "client_id": configuration.clientID,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
        ])
        let tokenResponse = try await performTokenRequest(request)
        return cache(tokenResponse)
    }

    private func exchangeAuthorizationCode(
        _ code: String,
        verifier: String,
        redirectURI: URL
    ) async throws -> TokenResponse {
        let request = try tokenRequest(parameters: [
            "client_id": configuration.clientID,
            "code": code,
            "code_verifier": verifier,
            "grant_type": "authorization_code",
            "redirect_uri": redirectURI.absoluteString
        ])
        return try await performTokenRequest(request)
    }

    private func performTokenRequest(_ request: URLRequest) async throws -> TokenResponse {
        let (data, response) = try await transport.data(for: request)
        guard response.statusCode == 200,
              let decoded = try? JSONDecoder().decode(TokenResponse.self, from: data),
              !decoded.accessToken.isEmpty,
              decoded.expiresIn > 0 else {
            throw GoogleCalendarError.tokenExchangeFailed
        }
        return decoded
    }

    private func cache(_ response: TokenResponse) -> String {
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

    private func tokenRequest(parameters: [String: String]) throws -> URLRequest {
        var components = URLComponents()
        components.queryItems = parameters.sorted(by: { $0.key < $1.key }).map {
            URLQueryItem(name: $0.key, value: $0.value)
        }
        guard let body = components.percentEncodedQuery?.data(using: .utf8) else {
            throw GoogleCalendarError.invalidConfiguration
        }
        var request = URLRequest(url: configuration.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        return request
    }
}
