import Foundation
import ReadrKit
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
import SafariServices
#endif

/// Drives the browser-based OAuth + PKCE flow (see docs/AUTH.md): generate PKCE,
/// start the loopback server, open a browser to the provider's authorize
/// endpoint, capture the redirect, then exchange the code for tokens.
///
/// Browser choice is per-platform: macOS opens the default browser (the app
/// stays running, so the loopback server keeps serving), while iOS presents an
/// **in-process** `SFSafariViewController` — launching external Safari would
/// background the app, suspend the `LoopbackHTTPServer`, and the
/// `127.0.0.1:1455` redirect would never be answered.
@MainActor
final class OAuthCoordinator: NSObject {
    private var server: LoopbackHTTPServer?
    /// Pending sign-in continuation. Non-nil exactly while a flow is in
    /// flight; `completeAuthorization` nils it before resuming, so the two
    /// finish paths (loopback callback vs. user tapping Done in Safari) can
    /// race without ever resuming twice.
    private var continuation: CheckedContinuation<URL, Error>?
    #if os(iOS)
    private var safariViewController: SFSafariViewController?
    #endif

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
            self.continuation = continuation
            let server = LoopbackHTTPServer(port: UInt16(port))
            self.server = server
            server.start(redirectBase: redirectBase, expectedPath: redirectURL.path) { [weak self] result in
                // The listener runs on the main queue, but the closure itself
                // isn't actor-isolated — hop back onto the main actor.
                Task { @MainActor in
                    self?.completeAuthorization(with: result)
                }
            }
            self.openBrowser(to: authorizeURL)
        }

        let code = try client.handleCallback(url: callbackURL, expectedState: state)
        return try await client.exchangeCode(code, pkce: pkce)
    }

    /// Single teardown funnel for every way the flow can end (loopback
    /// callback, user cancellation, presentation failure): release the
    /// listener/port, dismiss the in-process browser, and resume the
    /// continuation exactly once.
    private func completeAuthorization(with result: Result<URL, Error>) {
        guard let continuation else { return } // already finished
        self.continuation = nil
        server?.stop()
        server = nil
        #if os(iOS)
        safariViewController?.dismiss(animated: true)
        safariViewController = nil
        #endif
        continuation.resume(with: result)
    }

    private func openBrowser(to url: URL) {
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #elseif os(iOS)
        guard let presenter = Self.topViewController() else {
            completeAuthorization(with: .failure(
                AuthError.tokenExchangeFailed("no view controller available to present the sign-in browser")
            ))
            return
        }
        let safari = SFSafariViewController(url: url)
        safari.delegate = self
        safariViewController = safari
        presenter.present(safari, animated: true)
        #endif
    }

    #if os(iOS)
    /// The view controller to present Safari from: the key window's root
    /// (falling back to any window of a foreground scene), then down the
    /// `presentedViewController` chain so presenting over an existing sheet
    /// (Settings is one) doesn't fail.
    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let foreground = scenes.filter { $0.activationState == .foregroundActive }
        let windows = (foreground.isEmpty ? scenes : foreground).flatMap(\.windows)
        let window = windows.first(where: \.isKeyWindow) ?? windows.first
        var top = window?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
    #endif
}

#if os(iOS)
extension OAuthCoordinator: SFSafariViewControllerDelegate {
    /// User tapped Done (or otherwise dismissed Safari) without completing
    /// sign-in: stop the loopback server (freeing port 1455) and cancel.
    /// The controller is already dismissing itself — clear our reference
    /// first so `completeAuthorization` doesn't dismiss it a second time.
    func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
        safariViewController = nil
        completeAuthorization(with: .failure(AuthError.userCancelled))
    }
}
#endif
