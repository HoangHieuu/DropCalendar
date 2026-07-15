import CryptoKit
import Foundation

actor SnapCalAPIClient: AccountServicing, OptimizedCloudEventExtracting, OAuthTokenBrokering {
    private struct SessionTokenEnvelope: Decodable {
        let accessToken: String
        let accessTokenExpiresAt: Date
        let refreshToken: String
        let refreshTokenExpiresAt: Date

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case accessTokenExpiresAt = "access_token_expires_at"
            case refreshToken = "refresh_token"
            case refreshTokenExpiresAt = "refresh_token_expires_at"
        }
    }

    private struct GoogleTokenEnvelope: Decodable {
        let accessToken: String
        let expiresIn: Double
        let refreshToken: String?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case expiresIn = "expires_in"
            case refreshToken = "refresh_token"
        }
    }

    private struct ExchangeResponse: Decodable {
        let userID: String
        let email: String
        let invited: Bool
        let session: SessionTokenEnvelope
        let google: GoogleTokenEnvelope

        enum CodingKeys: String, CodingKey {
            case userID = "user_id"
            case email, invited, session, google
        }
    }

    private struct ExchangeRequest: Encodable {
        let authorizationCode: String
        let pkceVerifier: String
        let redirectURI: String
        let nonce: String
        let deviceID: String

        enum CodingKeys: String, CodingKey {
            case authorizationCode = "authorization_code"
            case pkceVerifier = "pkce_verifier"
            case redirectURI = "redirect_uri"
            case nonce
            case deviceID = "device_id"
        }
    }

    private struct RefreshRequest: Encodable {
        let refreshToken: String

        enum CodingKeys: String, CodingKey {
            case refreshToken = "refresh_token"
        }
    }

    private struct HostedURLResponse: Decodable {
        let url: URL
    }

    private struct ExtractionMetadata: Encodable {
        struct OCRLine: Encodable {
            let text: String
            let confidence: Double
            let box: TextRegion?
        }

        let schemaVersion = "2"
        let capturedAt: Date
        let timeZone: String
        let locale: String
        let ocrLines: [OCRLine]
        let retryPublicKey: String

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case capturedAt = "captured_at"
            case timeZone = "time_zone"
            case locale
            case ocrLines = "ocr_lines"
            case retryPublicKey = "retry_public_key"
        }
    }

    private struct ExtractionMetaResponse: Decodable {
        let requestID: String
        let quota: AccuracyQuota

        enum CodingKeys: String, CodingKey {
            case requestID = "request_id"
            case quota
        }
    }

    private struct RetryEnvelopeResponse: Decodable {
        let requestID: String
        let algorithm: String
        let envelopeBase64: String
        let expiresAt: Date

        enum CodingKeys: String, CodingKey {
            case requestID = "request_id"
            case algorithm
            case envelopeBase64 = "envelope_base64"
            case expiresAt = "expires_at"
        }
    }

    private struct APIErrorEnvelope: Decodable {
        struct Body: Decodable {
            let code: String
            let retryable: Bool
            let requestID: String

            enum CodingKeys: String, CodingKey {
                case code, retryable
                case requestID = "request_id"
            }
        }

        let error: Body
    }

    private struct SessionMemory {
        let accessToken: String
        let expiresAt: Date

        var isUsable: Bool { expiresAt.timeIntervalSinceNow > 60 }
    }

    private let baseURL: URL
    private let deviceID: String
    private let oauth: GoogleOAuthService
    private let oauthScope: String
    private let sessionStore: KeychainSecretStore
    private let retryKeyStore: KeychainSecretStore
    private let transport: any HTTPTransport
    private let preprocessor: AccuracyImagePreprocessor
    private let responseDecoder: AccuracyExtractionClient
    private let calendar: Calendar
    private let timeZone: TimeZone
    private let locale: Locale
    private var session: SessionMemory?
    private var cachedAccount: (snapshot: AccountSnapshot, expiresAt: Date)?

    init(
        baseURL: URL,
        deviceID: String,
        oauth: GoogleOAuthService,
        oauthScope: String,
        sessionStore: KeychainSecretStore,
        retryKeyStore: KeychainSecretStore,
        transport: any HTTPTransport = URLSessionHTTPTransport(),
        preprocessor: AccuracyImagePreprocessor = AccuracyImagePreprocessor(),
        calendar: Calendar = .current,
        timeZone: TimeZone = .current,
        locale: Locale = .current
    ) throws {
        guard Self.isAllowed(baseURL) else { throw SnapCalAccountError.notConfigured }
        self.baseURL = baseURL
        self.deviceID = deviceID
        self.oauth = oauth
        self.oauthScope = oauthScope
        self.sessionStore = sessionStore
        self.retryKeyStore = retryKeyStore
        self.transport = transport
        self.preprocessor = preprocessor
        self.calendar = calendar
        self.timeZone = timeZone
        self.locale = locale
        let decodeEndpoint = baseURL.appending(path: "/v1/extract")
        self.responseDecoder = try AccuracyExtractionClient(
            endpoint: decodeEndpoint,
            transport: transport,
            calendar: calendar,
            timeZone: timeZone,
            locale: locale,
            preprocessor: preprocessor
        )
    }

    static func live(baseURL: URL) throws -> SnapCalAPIClient {
        let deviceID = stableDeviceID()
        let configuration = GoogleOAuthConfiguration.live
        let googleStore = KeychainCredentialStore(account: configuration.clientID)
        return try SnapCalAPIClient(
            baseURL: baseURL,
            deviceID: deviceID,
            oauth: GoogleOAuthService(
                configuration: configuration,
                credentialStore: googleStore
            ),
            oauthScope: configuration.scope,
            sessionStore: KeychainSecretStore(
                service: "com.snapcal.app.session",
                account: deviceID
            ),
            retryKeyStore: KeychainSecretStore(
                service: "com.snapcal.app.retry-key",
                account: deviceID
            )
        )
    }

    func restoreSession() async throws -> AccountSnapshot? {
        guard let data = try sessionStore.read(),
              let refreshToken = String(data: data, encoding: .utf8),
              !refreshToken.isEmpty else {
            return nil
        }
        do {
            try await rotateSession(refreshToken: refreshToken)
            return try await loadAccount(force: true)
        } catch SnapCalAccountError.authenticationRequired {
            try? sessionStore.delete()
            session = nil
            cachedAccount = nil
            return nil
        }
    }

    func loadPlans() async throws -> [AccountPlan] {
        let request = URLRequest(url: endpoint("/v2/plans"), timeoutInterval: 20)
        let (data, response) = try await perform(request)
        guard response.statusCode == 200 else {
            throw accountError(data: data, status: response.statusCode)
        }
        return try decode([AccountPlan].self, from: data)
    }

    func signIn() async throws -> AccountSnapshot {
        let nonce = try OAuthSecurity.randomURLSafeString()
        let grant = try await oauth.authorizationGrant(
            scope: "openid email \(oauthScope)",
            promptConsent: false,
            nonce: nonce
        )
        let body = ExchangeRequest(
            authorizationCode: grant.code,
            pkceVerifier: grant.verifier,
            redirectURI: grant.redirectURI.absoluteString,
            nonce: nonce,
            deviceID: deviceID
        )
        let response: ExchangeResponse = try await jsonRequest(
            path: "/v2/auth/google/exchange",
            method: "POST",
            body: body,
            authenticated: false
        )
        try acceptSession(response.session)
        _ = await oauth.acceptInteractiveTokenResponse(OAuthTokenResponse(
            accessToken: response.google.accessToken,
            expiresIn: response.google.expiresIn,
            refreshToken: response.google.refreshToken
        ))
        return try await loadAccount(force: true)
    }

    func exchange(_ request: OAuthTokenBrokerRequest) async throws -> OAuthTokenResponse {
        do {
            let response: GoogleTokenEnvelope = try await jsonRequest(
                path: "/v2/auth/google/token",
                method: "POST",
                body: request,
                authenticated: true
            )
            return OAuthTokenResponse(
                accessToken: response.accessToken,
                expiresIn: response.expiresIn,
                refreshToken: response.refreshToken
            )
        } catch SnapCalAccountError.authenticationRequired {
            throw GoogleCalendarError.notAuthorized
        } catch SnapCalAccountError.invalidResponse {
            throw GoogleCalendarError.tokenExchangeFailed
        } catch {
            throw GoogleCalendarError.hostedOAuthUnavailable
        }
    }

    func refreshAccount() async throws -> AccountSnapshot {
        try await loadAccount(force: true)
    }

    func checkoutURL() async throws -> URL {
        let response: HostedURLResponse = try await jsonRequest(
            path: "/v2/billing/checkout",
            method: "POST",
            body: EmptyBody(),
            authenticated: true
        )
        return response.url
    }

    func portalURL() async throws -> URL {
        let response: HostedURLResponse = try await jsonRequest(
            path: "/v2/billing/portal",
            method: "POST",
            body: EmptyBody(),
            authenticated: true
        )
        return response.url
    }

    func signOut() async {
        if let access = try? await accessToken() {
            var request = URLRequest(url: endpoint("/v2/auth/logout"))
            request.httpMethod = "POST"
            request.setValue("Bearer \(access)", forHTTPHeaderField: "Authorization")
            _ = try? await transport.data(for: request)
        }
        try? sessionStore.delete()
        session = nil
        cachedAccount = nil
    }

    func prepare(image: ValidatedImage) async throws -> PreparedAccuracyImage {
        try await preprocessor.prepare(image.cgImage)
    }

    func extract(
        preparedImage: PreparedAccuracyImage,
        lines: [RecognizedTextLine],
        capturedAt: Date,
        sourceFileName: String
    ) async throws -> CloudExtractionResult {
        let access: String
        do {
            access = try await accessToken()
        } catch {
            throw CloudExtractionError.notConfigured
        }
        let retryKey = try retryPrivateKey()
        let submittedLines = AccuracyExtractionClient.boundedOCR(lines)
        let metadata = ExtractionMetadata(
            capturedAt: capturedAt,
            timeZone: timeZone.identifier,
            locale: locale.identifier,
            ocrLines: submittedLines.map {
                ExtractionMetadata.OCRLine(
                    text: $0.text,
                    confidence: $0.confidence,
                    box: $0.region
                )
            },
            retryPublicKey: Self.base64URL(retryKey.publicKey.rawRepresentation)
        )
        let metadataEncoder = JSONEncoder()
        metadataEncoder.dateEncodingStrategy = .iso8601
        let metadataData = try metadataEncoder.encode(metadata)
        let boundary = "SnapCal-\(UUID().uuidString)"
        let requestBody = multipartBody(
            boundary: boundary,
            metadata: metadataData,
            image: preparedImage.jpegData
        )
        let idempotencyKey = UUID().uuidString
        var request = URLRequest(url: endpoint("/v2/extractions"), timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("Bearer \(access)", forHTTPHeaderField: "Authorization")
        request.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = requestBody

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.data(for: request)
        } catch {
            do {
                (data, response) = try await transport.data(for: request)
            } catch {
                throw CloudExtractionError.unavailable
            }
        }
        if response.statusCode == 200 {
            let metadataResponse = try decode(ExtractionMetaResponse.self, from: data)
            if let account = cachedAccount?.snapshot {
                cachedAccount = (
                    AccountSnapshot(
                        userID: account.userID,
                        email: account.email,
                        invited: account.invited,
                        subscriptionStatus: account.subscriptionStatus,
                        plan: account.plan,
                        quota: metadataResponse.quota,
                        paymentWarning: account.paymentWarning
                    ),
                    Date().addingTimeInterval(15 * 60)
                )
            }
            let decoded = try responseDecoder.decodeResponse(
                data,
                lines: submittedLines,
                capturedAt: capturedAt,
                sourceFileName: sourceFileName
            )
            return CloudExtractionResult(
                drafts: decoded.drafts,
                model: decoded.model,
                quota: metadataResponse.quota
            )
        }
        let apiError = try? decode(APIErrorEnvelope.self, from: data).error
        if response.statusCode == 409,
           apiError?.code == "request_complete",
           let requestID = apiError?.requestID {
            let retryData = try await retrieveResult(
                requestID: requestID,
                accessToken: access,
                privateKey: retryKey
            )
            return try responseDecoder.decodeResponse(
                retryData,
                lines: submittedLines,
                capturedAt: capturedAt,
                sourceFileName: sourceFileName
            )
        }
        throw cloudError(code: apiError?.code, status: response.statusCode)
    }

    private func loadAccount(force: Bool) async throws -> AccountSnapshot {
        if !force,
           let cachedAccount,
           cachedAccount.expiresAt > Date() {
            return cachedAccount.snapshot
        }
        let access = try await accessToken()
        var request = URLRequest(url: endpoint("/v2/me"))
        request.setValue("Bearer \(access)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await perform(request)
        guard response.statusCode == 200 else {
            throw accountError(data: data, status: response.statusCode)
        }
        let snapshot = try decode(AccountSnapshot.self, from: data)
        cachedAccount = (snapshot, Date().addingTimeInterval(15 * 60))
        return snapshot
    }

    private func accessToken() async throws -> String {
        if let session, session.isUsable { return session.accessToken }
        guard let data = try sessionStore.read(),
              let refresh = String(data: data, encoding: .utf8),
              !refresh.isEmpty else {
            throw SnapCalAccountError.authenticationRequired
        }
        try await rotateSession(refreshToken: refresh)
        guard let session else { throw SnapCalAccountError.authenticationRequired }
        return session.accessToken
    }

    private func rotateSession(refreshToken: String) async throws {
        let body = RefreshRequest(refreshToken: refreshToken)
        let response: SessionTokenEnvelope = try await jsonRequest(
            path: "/v2/auth/session/refresh",
            method: "POST",
            body: body,
            authenticated: false
        )
        try acceptSession(response)
    }

    private func acceptSession(_ response: SessionTokenEnvelope) throws {
        guard !response.accessToken.isEmpty,
              response.accessTokenExpiresAt > Date(),
              response.refreshTokenExpiresAt > Date() else {
            throw SnapCalAccountError.invalidResponse
        }
        try sessionStore.write(Data(response.refreshToken.utf8))
        session = SessionMemory(
            accessToken: response.accessToken,
            expiresAt: response.accessTokenExpiresAt
        )
    }

    private func retryPrivateKey() throws -> Curve25519.KeyAgreement.PrivateKey {
        if let stored = try retryKeyStore.read() {
            do {
                return try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: stored)
            } catch {
                try? retryKeyStore.delete()
            }
        }
        let key = Curve25519.KeyAgreement.PrivateKey()
        try retryKeyStore.write(key.rawRepresentation)
        return key
    }

    private func retrieveResult(
        requestID: String,
        accessToken: String,
        privateKey: Curve25519.KeyAgreement.PrivateKey
    ) async throws -> Data {
        var request = URLRequest(url: endpoint("/v2/extractions/\(requestID)"))
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await perform(request)
        guard response.statusCode == 200 else {
            throw cloudError(
                code: (try? decode(APIErrorEnvelope.self, from: data).error.code),
                status: response.statusCode
            )
        }
        let retry = try decode(RetryEnvelopeResponse.self, from: data)
        guard retry.algorithm == "x25519-hkdf-sha256-chachapoly",
              retry.expiresAt > Date(),
              let envelope = Self.decodeBase64URL(retry.envelopeBase64) else {
            throw CloudExtractionError.invalidResponse
        }
        return try Self.openRetryEnvelope(envelope, privateKey: privateKey)
    }

    private func jsonRequest<Response: Decodable, Body: Encodable>(
        path: String,
        method: String,
        body: Body,
        authenticated: Bool
    ) async throws -> Response {
        var request = URLRequest(url: endpoint(path), timeoutInterval: 20)
        request.httpMethod = method
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        if authenticated {
            request.setValue("Bearer \(try await accessToken())", forHTTPHeaderField: "Authorization")
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(body)
        let (data, response) = try await perform(request)
        guard response.statusCode == 200 else {
            throw accountError(data: data, status: response.statusCode)
        }
        return try decode(Response.self, from: data)
    }

    private func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            return try await transport.data(for: request)
        } catch {
            throw SnapCalAccountError.unavailable
        }
    }

    private func decode<Value: Decodable>(_ type: Value.Type, from data: Data) throws -> Value {
        guard data.count <= 1_000_000 else { throw SnapCalAccountError.invalidResponse }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            if let date = Self.iso8601Fractional.date(from: value)
                ?? Self.iso8601.date(from: value) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: try decoder.singleValueContainer(),
                debugDescription: "Invalid ISO-8601 date"
            )
        }
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw SnapCalAccountError.invalidResponse
        }
    }

    private func accountError(data: Data, status: Int) -> SnapCalAccountError {
        let code = (try? decode(APIErrorEnvelope.self, from: data).error.code) ?? ""
        switch code {
        case "authentication_required", "session_expired", "invalid_refresh_token", "refresh_token_reused":
            return .authenticationRequired
        case "invitation_required": return .invitationRequired
        case "subscription_required": return .subscriptionRequired
        case "quota_exhausted": return .quotaExhausted
        case "rate_limit_exceeded", "daily_limit_exceeded", "concurrent_limit_exceeded": return .rateLimited
        case "provider_budget_exhausted": return .providerBudgetExhausted
        case "billing_unavailable", "webhook_dispatch_unavailable": return .billingUnavailable
        default: return status >= 500 ? .unavailable : .invalidResponse
        }
    }

    private func cloudError(code: String?, status: Int) -> CloudExtractionError {
        switch code {
        case "quota_exhausted": return .quotaExhausted
        case "subscription_required", "invitation_required", "authentication_required", "session_expired":
            return .notConfigured
        case "invalid_provider_output": return .invalidResponse
        case "provider_rejected_input", "invalid_image": return .rejected
        case "provider_budget_exhausted": return .providerBudgetExhausted
        case "timeout": return .timeout
        default: return status >= 500 ? .unavailable : .rejected
        }
    }

    private func multipartBody(boundary: String, metadata: Data, image: Data) -> Data {
        var body = Data()
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"metadata\"\r\n".utf8))
        body.append(Data("Content-Type: application/json; charset=utf-8\r\n\r\n".utf8))
        body.append(metadata)
        body.append(Data("\r\n--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"image\"; filename=\"screenshot.jpg\"\r\n".utf8))
        body.append(Data("Content-Type: image/jpeg\r\n\r\n".utf8))
        body.append(image)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        return body
    }

    private func endpoint(_ path: String) -> URL {
        URL(string: path, relativeTo: baseURL)!.absoluteURL
    }

    private static func openRetryEnvelope(
        _ envelope: Data,
        privateKey: Curve25519.KeyAgreement.PrivateKey
    ) throws -> Data {
        guard envelope.count > 61,
              envelope[envelope.startIndex] == 1 else {
            throw CloudExtractionError.invalidResponse
        }
        let ephemeralRange = 1..<33
        let nonceRange = 33..<45
        let ciphertextRange = 45..<(envelope.count - 16)
        let tagRange = (envelope.count - 16)..<envelope.count
        let ephemeral = try Curve25519.KeyAgreement.PublicKey(
            rawRepresentation: envelope.subdata(in: ephemeralRange)
        )
        let shared = try privateKey.sharedSecretFromKeyAgreement(with: ephemeral)
        let key = shared.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data(),
            sharedInfo: Data("snapcal-retry-v1".utf8),
            outputByteCount: 32
        )
        let nonce = try ChaChaPoly.Nonce(data: envelope.subdata(in: nonceRange))
        let sealed = try ChaChaPoly.SealedBox(
            nonce: nonce,
            ciphertext: envelope.subdata(in: ciphertextRange),
            tag: envelope.subdata(in: tagRange)
        )
        return try ChaChaPoly.open(sealed, using: key)
    }

    private static func stableDeviceID() -> String {
        let key = "SnapCalDeviceIdentifier"
        if let existing = UserDefaults.standard.string(forKey: key), !existing.isEmpty {
            return existing
        }
        let value = UUID().uuidString
        UserDefaults.standard.set(value, forKey: key)
        return value
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func decodeBase64URL(_ value: String) -> Data? {
        var normalized = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        normalized.append(String(repeating: "=", count: (4 - normalized.count % 4) % 4))
        return Data(base64Encoded: normalized)
    }

    private static func isAllowed(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), let host = url.host?.lowercased() else {
            return false
        }
        if scheme == "https" { return true }
        return scheme == "http" && ["127.0.0.1", "localhost"].contains(host)
    }

    private static let iso8601Fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

private struct EmptyBody: Encodable { }
