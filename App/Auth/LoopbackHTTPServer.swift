import Foundation
import Network

/// A one-shot loopback HTTP server that captures the OAuth redirect. The browser
/// is sent to `127.0.0.1:<port>/auth/callback?...`; we read that one request,
/// hand back the full callback URL, and reply with a small "you can close this"
/// page. Used because the providers use loopback redirect URIs (the Codex/Zed
/// pattern), which `ASWebAuthenticationSession` can't intercept.
final class LoopbackHTTPServer {
    private var listener: NWListener?
    private let port: UInt16
    private var didComplete = false

    init(port: UInt16) {
        self.port = port
    }

    /// Begin listening. `onCallback` fires once with the reconstructed callback
    /// URL (or an error), after which the server stops.
    func start(redirectBase: String, onCallback: @escaping (Result<URL, Error>) -> Void) {
        do {
            guard let nwPort = NWEndpoint.Port(rawValue: port) else {
                throw LoopbackError.invalidPort
            }
            let listener = try NWListener(using: .tcp, on: nwPort)
            self.listener = listener
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection, redirectBase: redirectBase, onCallback: onCallback)
            }
            listener.start(queue: .main)
        } catch {
            onCallback(.failure(error))
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func handle(
        _ connection: NWConnection,
        redirectBase: String,
        onCallback: @escaping (Result<URL, Error>) -> Void
    ) {
        connection.start(queue: .main)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, _, error in
            guard let self else { return }
            if let error {
                self.finish(.failure(error), connection: connection, onCallback: onCallback)
                return
            }
            guard let data, let request = String(data: data, encoding: .utf8),
                  let target = Self.requestTarget(request),
                  let url = URL(string: redirectBase + target) else {
                self.finish(.failure(LoopbackError.badRequest), connection: connection, onCallback: onCallback)
                return
            }
            self.respondOK(on: connection)
            self.finish(.success(url), connection: connection, onCallback: onCallback)
        }
    }

    private func respondOK(on connection: NWConnection) {
        let body = "<html><body style=\"font-family:-apple-system;padding:3rem;text-align:center\">"
            + "<h2>Signed in to Readr</h2><p>You can close this tab and return to the app.</p></body></html>"
        let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\n"
            + "Content-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in })
    }

    private func finish(
        _ result: Result<URL, Error>,
        connection: NWConnection,
        onCallback: @escaping (Result<URL, Error>) -> Void
    ) {
        guard !didComplete else { return }
        didComplete = true
        onCallback(result)
        connection.cancel()
        stop()
    }

    /// Extract the request target ("/auth/callback?...") from the request line.
    static func requestTarget(_ request: String) -> String? {
        guard let firstLine = request.split(separator: "\r\n", maxSplits: 1).first else { return nil }
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        return String(parts[1])
    }

    enum LoopbackError: Error { case invalidPort, badRequest }
}
