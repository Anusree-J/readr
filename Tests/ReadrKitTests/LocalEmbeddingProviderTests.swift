import XCTest
@testable import ReadrKit

final class LocalEmbeddingProviderTests: XCTestCase {

    func testEmbedIsDeterministic() async throws {
        let provider = LocalEmbeddingProvider()
        let text = "the quick brown fox jumps over the lazy dog"

        let first = try await provider.embed([text])
        let second = try await provider.embed([text])

        XCTAssertEqual(first.count, 1)
        XCTAssertEqual(second.count, 1)
        XCTAssertEqual(first[0], second[0], "Same input must yield identical vectors")
    }

    func testVectorsHaveCorrectDimensionAndAreNormalized() async throws {
        let provider = LocalEmbeddingProvider(dimensions: 256)
        let vectors = try await provider.embed(["hello world from the embedding provider"])
        let vector = try XCTUnwrap(vectors.first)

        XCTAssertEqual(vector.count, 256)

        let length = vector.reduce(Float(0)) { $0 + $1 * $1 }.squareRoot()
        XCTAssertEqual(length, 1.0, accuracy: 1e-4, "Non-empty vectors must be L2-normalized")
    }

    func testEmptyTextProducesZeroVector() async throws {
        let provider = LocalEmbeddingProvider(dimensions: 64)
        let vectors = try await provider.embed(["   "])
        let vector = try XCTUnwrap(vectors.first)
        XCTAssertEqual(vector.count, 64)
        XCTAssertTrue(vector.allSatisfy { $0 == 0 })
    }

    func testCosineSimilarityOfIdenticalTextsIsOne() async throws {
        let provider = LocalEmbeddingProvider()
        let vectors = try await provider.embed(["puppies and dogs love to play fetch"])
        let vector = try XCTUnwrap(vectors.first)

        let sim = LocalEmbeddingProvider.cosineSimilarity(vector, vector)
        XCTAssertEqual(sim, 1.0, accuracy: 1e-4)
    }

    func testDisjointVocabularyHasLowerSimilarity() async throws {
        let provider = LocalEmbeddingProvider()
        let dogText = "puppies dogs bark fetch leash kennel"
        let spaceText = "planets orbit galaxies comets nebula telescope"

        let dog = try XCTUnwrap(try await provider.embed([dogText]).first)
        let space = try XCTUnwrap(try await provider.embed([spaceText]).first)

        let selfSim = LocalEmbeddingProvider.cosineSimilarity(dog, dog)
        let crossSim = LocalEmbeddingProvider.cosineSimilarity(dog, space)

        XCTAssertLessThan(crossSim, selfSim)
        XCTAssertLessThan(crossSim, 0.5, "Disjoint vocabularies should be weakly similar")
    }

    func testCosineSimilarityWithZeroVectorIsZero() {
        let zero = [Float](repeating: 0, count: 8)
        let nonZero: [Float] = [1, 0, 0, 0, 0, 0, 0, 0]
        XCTAssertEqual(LocalEmbeddingProvider.cosineSimilarity(zero, nonZero), 0)
        XCTAssertEqual(LocalEmbeddingProvider.cosineSimilarity(nonZero, zero), 0)
    }

    func testIsLocalAndDefaultDimensions() {
        let provider = LocalEmbeddingProvider()
        XCTAssertTrue(provider.isLocal)
        XCTAssertEqual(provider.dimensions, 256)
    }
}
