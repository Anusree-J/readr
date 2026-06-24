import Foundation
import ReadrKit
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// Drives the browser-based OAuth + PKCE flow (see docs/AUTH.md): generate PKCE,
/// start the loopback server, open the system browser to the provider's
/// authorize endpoint, capture the redirect, then exchange the code for tokens.
@MainActor
final class OAuthCoordinator {
    private var server: LoopbackHTTPServer?

    func signIn(config: OAuthProviderConfig) async throws -> Credentials {
        let pkce = PKCE()
        let state = PKCE.randomState()

        guard let redirectURL = URL(string: config.redirectURI),
              let scheme = redirectURL.scheme,
              let host = redirectURL.host,
              let port = redirectURL.port else {
            throw AuthError.tokenExchangeFailed("invalid redirect URI")
        }
        let redirectBase = "\(scheme)://\(host):\(port)"
        let client = OAuthClient(config: config)
        let authorizeURL = client.authorizationURL(pkce: pkce, state: state)

        let callbackURL: URL = try await withCheckedThrowingContinuation { continuation in
            let server = LoopbackHTTPServer(port: UInt16(port))
            self.server = server
            server.start(redirectBase: redirectBase) { result in
                continuation.resume(with: result)
            }
            Self.openInBrowser(authorizeURL)
        }
        self.server = nil

        let code = try client.handleCallback(url: callbackURL, expectedState: state)
        return try await client.exchangeCode(code, pkce: pkce)
    }

    private static func openInBrowser(_ url: URL) {
        #if canImport(AppKit)
        NSWorkspace.shared.open(url)
        #elseif canImport(UIKit)
        UIApplication.shared.open(url)
        #endif
    }
}
