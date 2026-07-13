import Foundation
import Network

final class LoopbackOAuthServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "com.snapcal.oauth-loopback")
    private var callbackContinuation: CheckedContinuation<URL, Error>?
    private var pendingCallbackURL: URL?
    private var didStart = false
    private var didFinish = false

    init() throws {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredLocalEndpoint = .hostPort(
            host: NWEndpoint.Host("127.0.0.1"),
            port: .any
        )
        listener = try NWListener(using: parameters)
    }

    func start() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    guard !self.didStart else { return }
                    self.didStart = true
                    guard let port = self.listener.port,
                          let url = URL(string: "http://127.0.0.1:\(port.rawValue)") else {
                        continuation.resume(throwing: GoogleCalendarError.callbackFailed)
                        self.finish()
                        return
                    }
                    continuation.resume(returning: url)
                case .failed:
                    if !self.didStart {
                        self.didStart = true
                        continuation.resume(throwing: GoogleCalendarError.callbackFailed)
                    } else {
                        self.callbackContinuation?.resume(throwing: GoogleCalendarError.callbackFailed)
                        self.callbackContinuation = nil
                    }
                    self.finish()
                case .cancelled:
                    if !self.didStart && !self.didFinish {
                        self.didStart = true
                        continuation.resume(throwing: GoogleCalendarError.authorizationCancelled)
                    }
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.receiveRequest(on: connection)
            }
            listener.start(queue: queue)
        }
    }

    func waitForCallback() async throws -> URL {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                queue.async { [weak self] in
                    guard let self else {
                        continuation.resume(throwing: GoogleCalendarError.authorizationCancelled)
                        return
                    }
                    if let pendingCallbackURL = self.pendingCallbackURL {
                        self.pendingCallbackURL = nil
                        continuation.resume(returning: pendingCallbackURL)
                        return
                    }
                    guard !self.didFinish else {
                        continuation.resume(throwing: GoogleCalendarError.authorizationCancelled)
                        return
                    }
                    self.callbackContinuation = continuation
                }
            }
        } onCancel: {
            self.cancel()
        }
    }

    func cancel() {
        queue.async { [weak self] in
            guard let self, !self.didFinish else { return }
            self.callbackContinuation?.resume(throwing: GoogleCalendarError.authorizationCancelled)
            self.callbackContinuation = nil
            self.finish()
        }
    }

    private func receiveRequest(on connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, _ in
            guard let self else { return }
            let callbackURL = data.flatMap(self.callbackURL(from:))
            let response = callbackURL == nil
                ? self.httpResponse(status: "400 Bad Request", message: "SnapCal could not read this response. Return to the app and try again.")
                : self.httpResponse(status: "200 OK", message: "Authorization received. You can close this tab and return to SnapCal.")

            connection.send(content: response, completion: .contentProcessed { _ in
                connection.cancel()
            })

            guard let callbackURL, !self.didFinish else { return }
            if let continuation = self.callbackContinuation {
                self.callbackContinuation = nil
                continuation.resume(returning: callbackURL)
            } else {
                self.pendingCallbackURL = callbackURL
            }
            self.finish()
        }
    }

    private func callbackURL(from data: Data) -> URL? {
        guard let request = String(data: data, encoding: .utf8),
              let firstLine = request.components(separatedBy: "\r\n").first else {
            return nil
        }
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2, parts[0] == "GET", parts[1].hasPrefix("/") else {
            return nil
        }
        return URL(string: "http://127.0.0.1\(parts[1])")
    }

    private func httpResponse(status: String, message: String) -> Data {
        let html = """
        <!doctype html><html><head><meta charset="utf-8"><title>SnapCal</title></head>
        <body style="font-family:-apple-system;padding:48px;max-width:620px">
        <h1>SnapCal</h1><p>\(message)</p></body></html>
        """
        return Data("""
        HTTP/1.1 \(status)\r
        Content-Type: text/html; charset=utf-8\r
        Content-Length: \(html.utf8.count)\r
        Connection: close\r
        \r
        \(html)
        """.utf8)
    }

    private func finish() {
        didFinish = true
        listener.stateUpdateHandler = nil
        listener.newConnectionHandler = nil
        listener.cancel()
    }
}
