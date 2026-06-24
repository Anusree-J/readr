import XCTest
@testable import ReadrKit

final class ChunkerTests: XCTestCase {

    private func makeBook(chapters: [Chapter], title: String = "Test Book") -> Book {
        Book(
            metadata: BookMetadata(title: title),
            chapters: chapters,
            estimatedTokenCount: 0
        )
    }

    func testChunksNeverSpanChapters() {
        let ch1 = Chapter(title: "Alpha", order: 0, text: String(repeating: "alpha ", count: 500))
        let ch2 = Chapter(title: "Beta", order: 1, text: String(repeating: "beta ", count: 500))
        let book = makeBook(chapters: [ch1, ch2])

        let chunks = Chunker().chunk(book)
        XCTAssertFalse(chunks.isEmpty)

        // Every chunk maps to exactly one chapter, and its text must be drawn
        // only from that chapter's vocabulary.
        for chunk in chunks {
            if chunk.chapterIndex == 0 {
                XCTAssertTrue(chunk.text.contains("alpha"))
                XCTAssertFalse(chunk.text.contains("beta"))
            } else if chunk.chapterIndex == 1 {
                XCTAssertTrue(chunk.text.contains("beta"))
                XCTAssertFalse(chunk.text.contains("alpha"))
            } else {
                XCTFail("Unexpected chapter index \(chunk.chapterIndex)")
            }
        }
    }

    func testLongChapterProducesMultipleOverlappingChunks() {
        // Build a long chapter from many distinct numbered words so we can
        // detect overlap by shared tokens between adjacent chunks.
        let words = (0..<800).map { "word\($0)" }.joined(separator: " ")
        let chapter = Chapter(title: "Long", order: 0, text: words)
        let book = makeBook(chapters: [chapter])

        let chunker = Chunker(targetCharacters: 600, overlapCharacters: 150)
        let chunks = chunker.chunk(book)

        XCTAssertGreaterThan(chunks.count, 1, "A long chapter should produce multiple chunks")

        // Adjacent chunks should share some overlapping text.
        var sawOverlap = false
        for idx in 0..<(chunks.count - 1) {
            let tailWords = Set(chunks[idx].text.split(separator: " ").suffix(20).map(String.init))
            let headWords = Set(chunks[idx + 1].text.split(separator: " ").prefix(20).map(String.init))
            if !tailWords.isDisjoint(with: headWords) { sawOverlap = true }
        }
        XCTAssertTrue(sawOverlap, "Adjacent chunks should overlap")
    }

    func testLocatorsContainChapterNumbersAndTitles() {
        let ch1 = Chapter(title: "Introduction", order: 0, text: "Some intro text.")
        let ch2 = Chapter(title: nil, order: 1, text: "Untitled chapter text.")
        let book = makeBook(chapters: [ch1, ch2])

        let chunks = Chunker().chunk(book)
        let first = chunks.first { $0.chapterIndex == 0 }
        let second = chunks.first { $0.chapterIndex == 1 }

        XCTAssertEqual(first?.locator, "Ch. 1 (Introduction)")
        XCTAssertEqual(second?.locator, "Ch. 2")
    }

    func testContextualTextPrependsTitleAndLocator() {
        let chapter = Chapter(title: "Chapter One", order: 2, text: "Hello world.")
        let book = makeBook(chapters: [chapter], title: "My Great Book")

        let chunker = Chunker()
        let chunks = chunker.chunk(book)
        let chunk = try! XCTUnwrap(chunks.first)

        let contextual = chunker.contextualText(for: chunk, in: book)
        XCTAssertTrue(contextual.hasPrefix("From \"My Great Book\", Ch. 3 (Chapter One):\n"))
        XCTAssertTrue(contextual.contains("Hello world."))
    }

    func testShortChapterIsASingleChunk() {
        let chapter = Chapter(title: "Tiny", order: 0, text: "Just a little text.")
        let book = makeBook(chapters: [chapter])
        let chunks = Chunker(targetCharacters: 1200, overlapCharacters: 200).chunk(book)
        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks.first?.text, "Just a little text.")
    }
}
