import XCTest
@testable import ReadrKit

/// Regression tests for the v1 launch-readiness fixes:
///   - A5: URLError → actionable `HTTPError.transport` messages.
///   - A2: API-key validation state in `ProviderManager` + provider test calls.
///   - A3: Ollama readiness probe classification.
final class ReviewFixesLaunchTests: XCTestCase {

    // MARK: - A5: transport (URLError) mapping

    func testTimedOutHasActionableMessage() {
        let error = HTTPError.transport(.timedOut)
        let message = error.errorDescription ?? ""
        XCTAssertTrue(message.localizedCaseInsensitiveContains("timed out"), message)
        XCTAssertFalse(message.contains("operation couldn't be completed"), message)
        let recovery = error.recoverySuggestion ?? ""
        XCTAssertTrue(recovery.localizedCaseInsensitiveContains("try again"), recovery)
    }

    func testNotConnectedToInternetHasActionableMessage() {
        let error = HTTPError.transport(.notConnectedToInternet)
        let message = error.errorDescription ?? ""
        XCTAssertTrue(message.localizedCaseInsensitiveContains("offline"), message)
        let recovery = error.recoverySuggestion ?? ""
        XCTAssertTrue(recovery.localizedCaseInsensitiveContains("reconnect"), recovery)
    }

    func testCannotConnectToHostHasActionableMessage() {
        let error = HTTPError.transport(.cannotConnectToHost)
        let message = error.errorDescription ?? ""
        XCTAssertTrue(message.localizedCaseInsensitiveContains("reach"), message)
        let recovery = error.recoverySuggestion ?? ""
        XCTAssertFalse(recovery.isEmpty, "expected a recovery suggestion")
        XCTAssertFalse(message.contains("operation couldn't be completed"), message)
    }

    func testTransportErrorIsEquatableAndDistinct() {
        // The URLError→HTTPError.transport mapping lives in URLSessionHTTPClient;
        // assert the enum shape it produces stays Equatable and distinguishes
        // codes, so callers/tests can match on it.
        XCTAssertEqual(HTTPError.transport(.timedOut), HTTPError.transport(.timedOut))
        XCTAssertNotEqual(HTTPError.transport(.timedOut), HTTPError.transport(.notConnectedToInternet))
    }

    // MARK: - A2: OpenAI / Anthropic credential validation

    func testOpenAIValidateSucceedsOn200() async throws {
        let mock = MockHTTPClient()
        mock.sendHandler = { _ in HTTPResponse(status: 200) }
        let provider = OpenAIProvider(credentials: .apiKey("sk-test"), http: mock)
        try await provider.validateCredential()
        let recorded = try XCTUnwrap(mock.requests.first)
        XCTAssertEqual(recorded.url.absoluteString, "https://api.openai.com/v1/models")
        XCTAssertEqual(recorded.method, .get)
        XCTAssertEqual(recorded.headers["authorization"], "Bearer sk-test")
    }

    func testOpenAIValidateThrowsOn401() async {
        let mock = MockHTTPClient()
        mock.sendHandler = { _ in HTTPResponse(status: 401, body: Data("bad key".utf8)) }
        let provider = OpenAIProvider(credentials: .apiKey("sk-bad"), http: mock)
        do {
            try await provider.validateCredential()
            XCTFail("expected 401 to throw")
        } catch let error as HTTPError {
            XCTAssertEqual(error, .status(401, body: "bad key"))
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testAnthropicValidateSucceedsOn200() async throws {
        let mock = MockHTTPClient()
        mock.sendHandler = { _ in HTTPResponse(status: 200) }
        let provider = AnthropicProvider(credentials: .apiKey("sk-ant"), http: mock)
        try await provider.validateCredential()
        let recorded = try XCTUnwrap(mock.requests.first)
        XCTAssertEqual(recorded.url.absoluteString, "https://api.anthropic.com/v1/messages")
        XCTAssertEqual(recorded.method, .post)
        XCTAssertEqual(recorded.headers["x-api-key"], "sk-ant")
    }

    func testAnthropicValidateThrowsOn403() async {
        let mock = MockHTTPClient()
        mock.sendHandler = { _ in HTTPResponse(status: 403) }
        let provider = AnthropicProvider(credentials: .apiKey("sk-bad"), http: mock)
        do {
            try await provider.validateCredential()
            XCTFail("expected 403 to throw")
        } catch let error as HTTPError {
            XCTAssertEqual(error, .status(403, body: ""))
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    // MARK: - A2: ProviderManager validation state

    /// A factory that builds real providers against a scripted HTTP mock, so we
    /// can drive validate() end-to-end through ProviderManager.
    private func makeManager(
        store: FakeCredentialStore,
        http: HTTPClient
    ) -> ProviderManager {
        ProviderManager(store: store, factory: DefaultProviderFactory.factory(http: http))
    }

    func testValidateStaysUnvalidatedOn401() async throws {
        let store = FakeCredentialStore()
        try store.save(.apiKey("sk-bad"), for: .openAI)
        let mock = MockHTTPClient()
        mock.sendHandler = { _ in HTTPResponse(status: 401) }
        let manager = makeManager(store: store, http: mock)

        // A stored-but-unvalidated remote key is not yet "active".
        let state = await manager.validate(.openAI)
        guard case .invalid = state else {
            return XCTFail("expected .invalid, got \(state)")
        }
        XCTAssertFalse(manager.isValidated(.openAI))
        XCTAssertFalse(manager.isConfigured(.openAI), "401 key must not count as configured")
    }

    func testValidateBecomesActiveOn200() async throws {
        let store = FakeCredentialStore()
        try store.save(.apiKey("sk-good"), for: .openAI)
        let mock = MockHTTPClient()
        mock.sendHandler = { _ in HTTPResponse(status: 200) }
        let manager = makeManager(store: store, http: mock)

        let state = await manager.validate(.openAI)
        XCTAssertEqual(state, .active)
        XCTAssertTrue(manager.isValidated(.openAI))
        XCTAssertTrue(manager.isConfigured(.openAI))
    }

    func testValidateMissingCredentialIsInvalid() async {
        let store = FakeCredentialStore()
        let mock = MockHTTPClient()
        let manager = makeManager(store: store, http: mock)

        let state = await manager.validate(.anthropic)
        guard case .invalid = state else {
            return XCTFail("expected .invalid, got \(state)")
        }
        XCTAssertTrue(mock.requests.isEmpty, "no network call when nothing is stored")
    }

    func testValidationDoesNotBreakSelectionPersistence() {
        let defaults = UserDefaults(suiteName: "readr.test.\(UUID().uuidString)")!
        let store = FakeCredentialStore()
        let manager = ProviderManager(
            store: store,
            factory: DefaultProviderFactory.factory(http: MockHTTPClient()),
            persistingIn: defaults
        )
        manager.setActive(kind: .openAI, modelID: "gpt-4.1-mini")

        // A fresh manager restores the persisted selection.
        let restored = ProviderManager(
            store: store,
            factory: DefaultProviderFactory.factory(http: MockHTTPClient()),
            persistingIn: defaults
        )
        XCTAssertEqual(restored.selection?.kind, .openAI)
        XCTAssertEqual(restored.selection?.modelID, "gpt-4.1-mini")
    }

    // MARK: - A3: Ollama probe classification + ProviderManager .local readiness

    func testProbeReadyWhenModelInstalled() async {
        let mock = MockHTTPClient()
        mock.sendHandler = { _ in
            HTTPResponse(status: 200, body: Data(#"{"models":[{"name":"llama3:latest"},{"name":"qwen2.5"}]}"#.utf8))
        }
        let provider = LocalLLMProvider(model: "llama3", http: mock)
        let result = await provider.probe()
        XCTAssertEqual(result, .ready)
    }

    func testProbeModelMissingWhenTagAbsent() async {
        let mock = MockHTTPClient()
        mock.sendHandler = { _ in
            HTTPResponse(status: 200, body: Data(#"{"models":[{"name":"qwen2.5"}]}"#.utf8))
        }
        let provider = LocalLLMProvider(model: "llama3", http: mock)
        let result = await provider.probe()
        XCTAssertEqual(result, .modelMissing(requested: "llama3", available: ["qwen2.5"]))
    }

    func testProbeNotRunningOnConnectionRefused() async {
        let mock = MockHTTPClient()
        mock.sendHandler = { _ in throw URLError(.cannotConnectToHost) }
        let provider = LocalLLMProvider(model: "llama3", http: mock)
        let result = await provider.probe()
        XCTAssertEqual(result, .notRunning)
    }

    func testProbeHitsTagsEndpoint() async throws {
        let mock = MockHTTPClient()
        mock.sendHandler = { _ in HTTPResponse(status: 200, body: Data(#"{"models":[]}"#.utf8)) }
        let provider = LocalLLMProvider(model: "llama3", http: mock)
        _ = await provider.probe()
        let recorded = try XCTUnwrap(mock.requests.first)
        XCTAssertEqual(recorded.url.host, "127.0.0.1")
        XCTAssertEqual(recorded.url.port, 11434)
        XCTAssertEqual(recorded.url.path, "/api/tags")
        XCTAssertEqual(recorded.method, .get)
    }

    func testManagerLocalReadinessReflectsProbe() async {
        let store = FakeCredentialStore()

        // Server up, model present → local becomes active/configured.
        let ready = MockHTTPClient()
        ready.sendHandler = { _ in
            HTTPResponse(status: 200, body: Data(#"{"models":[{"name":"llama3"}]}"#.utf8))
        }
        let readyManager = makeManager(store: store, http: ready)
        let readyState = await readyManager.validate(.local)
        XCTAssertEqual(readyState, .active)
        XCTAssertTrue(readyManager.isConfigured(.local))

        // Server down → local is no longer treated as configured.
        let down = MockHTTPClient()
        down.sendHandler = { _ in throw URLError(.cannotConnectToHost) }
        let downManager = makeManager(store: store, http: down)
        let state = await downManager.validate(.local)
        guard case .invalid = state else {
            return XCTFail("expected .invalid for down server, got \(state)")
        }
        XCTAssertFalse(downManager.isConfigured(.local), "down Ollama must not count as configured")
    }
}
