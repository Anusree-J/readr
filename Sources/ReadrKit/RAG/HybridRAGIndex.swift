import Foundation

/// In-memory hybrid (vector + BM25) retrieval index implementing
/// Anthropic-style Contextual Retrieval.
///
/// SQLite/`sqlite-vec` persistence is a later milestone; this implementation
/// keeps everything in memory, guarded by an `NSLock` for thread safety.
public final class HybridRAGIndex: RAGIndex, @unchecked Sendable {

    /// Everything stored for a single book.
    private struct BookIndex {
        var chunks: [Chunk]
        /// Contextual embedding vector per chunk (parallel to `chunks`).
        var vectors: [[Float]]
        /// Per-chunk term-frequency multiset over the contextual text.
        var termCounts: [[String: Int]]
        /// Per-chunk token length (sum of term frequencies).
        var docLengths: [Int]
        /// Document frequency: number of chunks containing each term.
        var documentFrequency: [String: Int]
        /// Average document length across all chunks.
        var averageDocLength: Double
    }

    private let chunker: Chunker
    private let lock = NSLock()
    private var indexes: [UUID: BookIndex] = [:]

    // BM25 parameters.
    private let k1: Double = 1.5
    private let b: Double = 0.75

    public init(chunker: Chunker = Chunker()) {
        self.chunker = chunker
    }

    // MARK: - RAGIndex

    public func build(for book: Book, embeddings: EmbeddingProvider) async throws {
        let chunks = chunker.chunk(book)

        // Embed the *contextual* text of each chunk (situating prefix included).
        let contextualTexts = chunks.map { chunker.contextualText(for: $0, in: book) }
        let vectors = chunks.isEmpty ? [] : try await embeddings.embed(contextualTexts)

        // Lexical bookkeeping is also over the contextual text so prefixes
        // (book title / chapter) contribute to BM25 just like vector search.
        var termCounts: [[String: Int]] = []
        var docLengths: [Int] = []
        var documentFrequency: [String: Int] = [:]

        for contextual in contextualTexts {
            let tokens = LocalEmbeddingProvider.tokenize(contextual)
            var counts: [String: Int] = [:]
            for token in tokens { counts[token, default: 0] += 1 }
            termCounts.append(counts)
            docLengths.append(tokens.count)
            for term in counts.keys { documentFrequency[term, default: 0] += 1 }
        }

        let totalLength = docLengths.reduce(0, +)
        let averageDocLength = chunks.isEmpty ? 0 : Double(totalLength) / Double(chunks.count)

        let entry = BookIndex(
            chunks: chunks,
            vectors: vectors,
            termCounts: termCounts,
            docLengths: docLengths,
            documentFrequency: documentFrequency,
            averageDocLength: averageDocLength
        )

        lock.lock()
        indexes[book.id] = entry  // Idempotent: rebuild replaces prior state.
        lastProvider = embeddings  // Reuse the same provider to embed queries.
        lock.unlock()
    }

    public func retrieve(query: String, bookID: UUID, limit: Int) async throws -> [RetrievedPassage] {
        lock.lock()
        let entry = indexes[bookID]
        lock.unlock()

        guard let entry, !entry.chunks.isEmpty, limit > 0 else { return [] }

        // Vector score: cosine of query embedding vs each chunk embedding.
        let queryVectors = try await embeddingProvider.embed([query])
        let queryVector = queryVectors.first ?? []

        let count = entry.chunks.count
        var vectorScores = [Double](repeating: 0, count: count)
        for idx in 0..<count {
            let sim = LocalEmbeddingProvider.cosineSimilarity(queryVector, entry.vectors[idx])
            vectorScores[idx] = Double(sim)
        }

        // BM25 lexical score over query terms.
        let queryTerms = LocalEmbeddingProvider.tokenize(query)
        var bm25Scores = [Double](repeating: 0, count: count)
        let n = Double(count)
        for term in Set(queryTerms) {
            let df = Double(entry.documentFrequency[term] ?? 0)
            guard df > 0 else { continue }
            let idf = log((n - df + 0.5) / (df + 0.5) + 1)
            for idx in 0..<count {
                let tf = Double(entry.termCounts[idx][term] ?? 0)
                guard tf > 0 else { continue }
                let denom = tf + k1 * (1 - b + b * Double(entry.docLengths[idx]) / max(entry.averageDocLength, 1e-9))
                bm25Scores[idx] += idf * (tf * (k1 + 1)) / denom
            }
        }

        // Min-max normalize each signal across candidates, then fuse 50/50.
        let normVector = Self.minMaxNormalize(vectorScores)
        let normBM25 = Self.minMaxNormalize(bm25Scores)

        var ranked: [(index: Int, score: Double)] = []
        ranked.reserveCapacity(count)
        for idx in 0..<count {
            let combined = 0.5 * normVector[idx] + 0.5 * normBM25[idx]
            ranked.append((idx, combined))
        }

        ranked.sort { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.index < rhs.index  // Stable tie-break for determinism.
        }

        return ranked.prefix(limit).map { item in
            let chunk = entry.chunks[item.index]
            return RetrievedPassage(text: chunk.text, locator: chunk.locator, score: item.score)
        }
    }

    public func isBuilt(bookID: UUID) async -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if let entry = indexes[bookID] {
            return !entry.chunks.isEmpty
        }
        return false
    }

    // MARK: - Internals

    /// The provider used to embed queries at retrieval time. The same kind of
    /// provider must be used for `build` and `retrieve`; we capture the most
    /// recent one to embed queries.
    private var lastProvider: EmbeddingProvider?

    /// Local default so query embedding works even if `build` was never given a
    /// custom provider variant. Overwritten on each `build`.
    private var embeddingProvider: EmbeddingProvider {
        lock.lock()
        defer { lock.unlock() }
        return lastProvider ?? LocalEmbeddingProvider()
    }

    static func minMaxNormalize(_ values: [Double]) -> [Double] {
        guard let minValue = values.min(), let maxValue = values.max() else {
            return values
        }
        let range = maxValue - minValue
        guard range > 0 else {
            // All equal — return zeros so this signal doesn't bias the fusion.
            return [Double](repeating: 0, count: values.count)
        }
        return values.map { ($0 - minValue) / range }
    }
}
