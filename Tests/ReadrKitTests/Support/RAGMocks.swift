import Foundation
@testable import ReadrKit

/// Shared M3 test doubles for retrieval-dependent suites.

/// A `RAGIndex` that returns canned passages and records which books were built.
final class StubRAGIndex: RAGIndex, @unchecked Sendable {
    var passages: [RetrievedPassage]
    private let lock = NSLock()
    private var built: Set<UUID> = []
    private(set) var retrieveCallCount = 0

    init(passages: [RetrievedPassage] = [RetrievedPassage(text: "a relevant passage", locator: "Ch. 1", score: 1.0)]) {
        self.passages = passages
    }

    func build(for book: Book, embeddings: EmbeddingProvider) async throws {
        lock.lock(); built.insert(book.id); lock.unlock()
    }

    func retrieve(query: String, bookID: UUID, limit: Int) async throws -> [RetrievedPassage] {
        lock.lock(); retrieveCallCount += 1; lock.unlock()
        return Array(passages.prefix(limit))
    }

    func isBuilt(bookID: UUID) async -> Bool {
        lock.lock(); defer { lock.unlock() }; return built.contains(bookID)
    }
}

/// Deterministic local embedding (no network) for index tests.
final class DeterministicEmbeddingProvider: EmbeddingProvider, @unchecked Sendable {
    let dimensions: Int
    let isLocal = true

    init(dimensions: Int = 16) { self.dimensions = dimensions }

    func embed(_ texts: [String]) async throws -> [[Float]] {
        texts.map { text in
            var vector = [Float](repeating: 0, count: dimensions)
            for token in text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }) {
                let bucket = abs(token.hashValue) % dimensions
                vector[bucket] += 1
            }
            return vector
        }
    }
}
