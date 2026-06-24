import Foundation

/// A deterministic, on-device, zero-network embedding provider.
///
/// Uses the "hashing trick": tokens (and adjacent bigrams) are mapped into a
/// fixed-dimensional vector via a *stable* FNV-1a hash, then the vector is
/// L2-normalized. This is fully deterministic across processes and machines —
/// it never uses Swift's randomized `Hasher`/`hashValue`.
public struct LocalEmbeddingProvider: EmbeddingProvider {
    public let dimensions: Int
    public var isLocal: Bool { true }

    public init(dimensions: Int = 256) {
        self.dimensions = max(1, dimensions)
    }

    public func embed(_ texts: [String]) async throws -> [[Float]] {
        texts.map { vector(for: $0) }
    }

    // MARK: - Embedding

    func vector(for text: String) -> [Float] {
        var vec = [Float](repeating: 0, count: dimensions)
        let tokens = Self.tokenize(text)
        guard !tokens.isEmpty else { return vec }

        // Unigrams.
        for token in tokens {
            let bucket = Int(Self.fnv1a(token) % UInt64(dimensions))
            vec[bucket] += 1
        }

        // Adjacent bigrams add a little local-order semantics.
        if tokens.count >= 2 {
            for idx in 0..<(tokens.count - 1) {
                let bigram = tokens[idx] + "\u{1}" + tokens[idx + 1]
                let bucket = Int(Self.fnv1a(bigram) % UInt64(dimensions))
                vec[bucket] += 0.5
            }
        }

        Self.l2NormalizeInPlace(&vec)
        return vec
    }

    // MARK: - Tokenization

    /// Lowercase, split on any non-alphanumeric character.
    static func tokenize(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        for scalar in text.lowercased().unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                current.unicodeScalars.append(scalar)
            } else if !current.isEmpty {
                tokens.append(current)
                current = ""
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    // MARK: - Stable hash (FNV-1a, 64-bit)

    /// Deterministic FNV-1a over the UTF-8 bytes of `string`. Independent of any
    /// per-process seed, unlike `Hasher`.
    static func fnv1a(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        let prime: UInt64 = 0x100000001b3
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* prime
        }
        return hash
    }

    // MARK: - Math

    static func l2NormalizeInPlace(_ vec: inout [Float]) {
        var sumSquares: Float = 0
        for value in vec { sumSquares += value * value }
        let norm = sumSquares.squareRoot()
        guard norm > 0 else { return }
        for idx in vec.indices { vec[idx] /= norm }
    }

    /// Cosine similarity. Returns 0 if either vector is zero or lengths differ.
    public static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0
        var normA: Float = 0
        var normB: Float = 0
        for idx in a.indices {
            dot += a[idx] * b[idx]
            normA += a[idx] * a[idx]
            normB += b[idx] * b[idx]
        }
        guard normA > 0, normB > 0 else { return 0 }
        return dot / (normA.squareRoot() * normB.squareRoot())
    }
}
