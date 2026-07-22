import XCTest
@testable import ReadrKit

/// Activation policy around saving a new provider credential (issue #44).
///
/// Saving a key must never displace a *working* active provider before the new
/// credential has been validated: activation is immediate only when nothing
/// usable holds the active slot, and otherwise waits for validation to settle
/// anything other than a proven-bad `.invalid`.
final class ProviderActivationTests: XCTestCase {

    /// `LLMProvider` whose `validateCredential()` outcome is scripted, so
    /// tests can steer `ProviderManager.validate(_:)` to `.active`,
    /// `.invalid`, or `.unavailable` without any network.
    private struct ValidatingMockProvider: LLMProvider, CredentialValidating {
        let info: ProviderInfo
        let validationError: Error?

        func stream(_ request: ChatRequest) -> AsyncThrowingStream<ChatChunk, Error> {
            AsyncThrowingStream { $0.finish() }
        }
        func countTokens(_ text: String) throws -> Int { max(1, text.count / 4) }
        func validateCredential() async throws {
            if let validationError { throw validationError }
        }
    }

    /// Factory that hands each kind a `ValidatingMockProvider` with a
    /// per-kind scripted validation outcome (nil error = accepted).
    private final class ScriptedFactory: @unchecked Sendable {
        private let lock = NSLock()
        private var errors: [ProviderInfo.Kind: Error] = [:]

        func scriptValidationError(_ error: Error?, for kind: ProviderInfo.Kind) {
            lock.lock(); defer { lock.unlock() }
            errors[kind] = error
        }

        var make: ProviderManager.ProviderFactory {
            { [weak self] info, _ in
                var error: Error?
                if let self {
                    self.lock.lock()
                    error = self.errors[info.kind]
                    self.lock.unlock()
                }
                return ValidatingMockProvider(info: info, validationError: error)
            }
        }
    }

    private var store: FakeCredentialStore!
    private var factory: ScriptedFactory!
    private var manager: ProviderManager!

    override func setUp() {
        super.setUp()
        store = FakeCredentialStore()
        factory = ScriptedFactory()
        manager = ProviderManager(store: store, factory: factory.make)
    }

    private let rejection = HTTPError.status(401, body: "invalid x-api-key")
    private let outage = HTTPError.status(503, body: "overloaded")

    /// Establish openAI as a stored, validated, active provider — the
    /// "working provider" a bad save must not displace.
    private func establishWorkingOpenAI() async throws {
        try store.save(.apiKey("sk-good"), for: .openAI)
        manager.setActive(kind: .openAI)
        _ = await manager.validate(.openAI)
        XCTAssertEqual(manager.validationState(.openAI), .active)
        XCTAssertEqual(manager.selection?.kind, .openAI)
    }

    // MARK: - The #44 regression

    func testInvalidKeySaveDoesNotStealActiveSelection() async throws {
        try await establishWorkingOpenAI()

        // Save a bad Anthropic key — the flow SettingsModel.saveAPIKey runs.
        try store.save(.apiKey("sk-ant-bad"), for: .anthropic)
        factory.scriptValidationError(rejection, for: .anthropic)
        manager.clearValidation(.anthropic)

        // A usable provider holds the slot, so no immediate takeover…
        XCTAssertFalse(
            manager.requestActivation(of: .anthropic),
            "Saving a key must not immediately displace a usable active provider"
        )
        XCTAssertEqual(manager.selection?.kind, .openAI)

        // …and a rejected credential never completes the takeover.
        let settled = await manager.validateAndActivate(.anthropic)
        guard case .invalid = settled else {
            return XCTFail("Expected .invalid, got \(String(describing: settled))")
        }
        XCTAssertEqual(
            manager.selection?.kind, .openAI,
            "A rejected key must leave the previously-active provider selected"
        )
        // The working provider is still resolvable — Ask keeps working.
        XCTAssertEqual(try manager.activeProvider()?.info.kind, .openAI)
    }

    // MARK: - Immediate activation when nothing usable holds the slot

    func testRequestActivationImmediateWhenNoSelection() throws {
        try store.save(.apiKey("sk-first"), for: .anthropic)

        XCTAssertTrue(
            manager.requestActivation(of: .anthropic),
            "The first-ever provider should become active immediately (onboarding stays optimistic)"
        )
        XCTAssertEqual(manager.selection?.kind, .anthropic)
    }

    func testRequestActivationImmediateWhenSelectedKindHasNoCredential() throws {
        // openAI was active but its credential is gone (disconnected).
        manager.setActive(kind: .openAI)

        try store.save(.apiKey("sk-new"), for: .anthropic)
        XCTAssertTrue(
            manager.requestActivation(of: .anthropic),
            "A selection pointing at a credential-less kind holds nothing usable — takeover is immediate"
        )
        XCTAssertEqual(manager.selection?.kind, .anthropic)
    }

    func testRequestActivationForAlreadyActiveKindIsNoOpButTrue() async throws {
        try await establishWorkingOpenAI()
        let before = manager.selection

        XCTAssertTrue(manager.requestActivation(of: .openAI))
        XCTAssertEqual(manager.selection, before, "Re-saving the active kind's key must keep its model choice")
    }

    // MARK: - Deferred activation lands after validation clears the key

    func testValidateAndActivateActivatesOnAcceptedKey() async throws {
        try await establishWorkingOpenAI()

        try store.save(.apiKey("sk-ant-good"), for: .anthropic)
        factory.scriptValidationError(nil, for: .anthropic)
        manager.clearValidation(.anthropic)
        XCTAssertFalse(manager.requestActivation(of: .anthropic))

        let settled = await manager.validateAndActivate(.anthropic)
        XCTAssertEqual(settled, .active)
        XCTAssertEqual(
            manager.selection?.kind, .anthropic,
            "An accepted key completes the deferred takeover"
        )
    }

    func testValidateAndActivateActivatesOnTransientFailure() async throws {
        try await establishWorkingOpenAI()

        // A 5xx/offline blip is not a rejection — the key stays optimistically
        // usable, matching activeProvider()'s treatment of .unavailable.
        try store.save(.apiKey("sk-ant-maybe"), for: .anthropic)
        factory.scriptValidationError(outage, for: .anthropic)
        manager.clearValidation(.anthropic)

        let settled = await manager.validateAndActivate(.anthropic)
        guard case .unavailable = settled else {
            return XCTFail("Expected .unavailable, got \(String(describing: settled))")
        }
        XCTAssertEqual(
            manager.selection?.kind, .anthropic,
            "A transient failure must not be treated as a rejection"
        )
    }

    func testValidateAndActivatePreservesSettledValidationState() async throws {
        try store.save(.apiKey("sk-ant-good"), for: .anthropic)
        factory.scriptValidationError(nil, for: .anthropic)

        _ = await manager.validateAndActivate(.anthropic)
        XCTAssertEqual(
            manager.validationState(.anthropic), .active,
            "Activation must not wipe the validation result that just authorized it"
        )
        XCTAssertTrue(manager.isValidated(.anthropic))
    }

    func testValidateAndActivateKeepsModelChoiceForSameKind() async throws {
        try store.save(.apiKey("sk-good"), for: .openAI)
        manager.setActive(kind: .openAI, modelID: "gpt-4.1-mini")

        // Re-saving a key for the already-selected kind re-validates it but
        // must not reset the user's model choice to the catalog default.
        factory.scriptValidationError(nil, for: .openAI)
        manager.clearValidation(.openAI)
        _ = await manager.validateAndActivate(.openAI)

        XCTAssertEqual(manager.selection?.modelID, "gpt-4.1-mini")
    }
}
