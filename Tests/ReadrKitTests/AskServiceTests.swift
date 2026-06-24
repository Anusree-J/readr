import XCTest
@testable import ReadrKit

final class AskServiceTests: XCTestCase {

    // MARK: - Fixtures

    private func makeBook(tokenCount: Int) -> Book {
        Book(
            metadata: BookMetadata(title: "Test Book", authors: ["A. Author"]),
            chapters: [Chapter(title: "One", order: 0, text: "Hello world. This is the only chapter.")],
            estimatedTokenCount: tokenCount
        )
    }

    /// Collect every event from the stream into an array.
    private func collect(
        _ stream: AsyncThrowingStream<AskEvent, Error>
    ) async throws -> [AskEvent] {
        var events: [AskEvent] = []
        for try await event in stream {
            events.append(event)
        }
        return events
    }

    // MARK: - Whole-book tier

    func testSmallBookUsesWholeBookTierAndCachesFullText() async throws {
        let book = makeBook(tokenCount: 100)
        let provider = MockLLMProvider(
            info: .fixture(
                kind: .anthropic,
                contextBudget: 200_000,
                supportsPromptCaching: true
            ),
            scriptedChunks: ["Hel", "lo"]
        )
        let strategy = AdaptiveContextStrategy(index: StubRAGIndex())
        let service = AskService(strategy: strategy, provider: provider)

        let events = try await collect(service.ask("What happens?", about: book, selection: nil))

        XCTAssertEqual(events.first, .contextAssembled(tier: .wholeBook))

        let tokens = events.compactMap { event -> String? in
            if case let .token(delta) = event { return delta }
            return nil
        }
        XCTAssertEqual(tokens.joined(), "Hello")
        XCTAssertEqual(events.last, .completed("Hello"))

        // The whole book is sent as a cacheable prefix, not as a plain message.
        let request = try XCTUnwrap(provider.receivedRequests.first)
        XCTAssertEqual(request.cacheableSystemPrefix, book.fullText)
    }

    // MARK: - Retrieval tier

    func testLargeBookUsesRetrievalTierAndQueriesIndex() async throws {
        let book = makeBook(tokenCount: 5_000_000)
        let provider = MockLLMProvider(
            info: .fixture(
                kind: .anthropic,
                contextBudget: 200_000,
                supportsPromptCaching: true
            )
        )
        let index = StubRAGIndex()
        let strategy = AdaptiveContextStrategy(index: index)
        let service = AskService(strategy: strategy, provider: provider)

        let events = try await collect(service.ask("What happens?", about: book, selection: nil))

        XCTAssertEqual(events.first, .contextAssembled(tier: .retrieval))
        XCTAssertEqual(index.retrieveCallCount, 1)
    }

    // MARK: - Selection anchor

    func testSelectionAnchorAppearsInUserMessage() async throws {
        let book = makeBook(tokenCount: 100)
        let provider = MockLLMProvider(
            info: .fixture(
                kind: .anthropic,
                contextBudget: 200_000,
                supportsPromptCaching: true
            )
        )
        let strategy = AdaptiveContextStrategy(index: StubRAGIndex())
        let service = AskService(strategy: strategy, provider: provider)

        let selection = Selection(
            chapterID: book.chapters[0].id,
            quotedText: "the selected sentence",
            surroundingText: "before the selected sentence after",
            chapterTitle: "One"
        )

        _ = try await collect(service.ask("Explain this.", about: book, selection: selection))

        let request = try XCTUnwrap(provider.receivedRequests.first)
        let userMessage = try XCTUnwrap(request.messages.first { $0.role == .user })
        XCTAssertTrue(
            userMessage.content.contains("the selected sentence"),
            "Expected the user message to carry the selection anchor; got: \(userMessage.content)"
        )
    }
}
