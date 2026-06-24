import XCTest
@testable import ReadrKit

/// J3 — highlight creation logic.
final class HighlightServiceTests: XCTestCase {

    private let service = HighlightService()

    private func fixture() -> (Book, Chapter) {
        let chapter = Chapter(title: "One", order: 0, text: "It was a bright cold day.")
        let book = Book(
            metadata: BookMetadata(title: "1984"),
            chapters: [chapter],
            estimatedTokenCount: 6
        )
        return (book, chapter)
    }

    func testMakeHighlightExtractsQuotedText() throws {
        let (book, chapter) = fixture()
        let highlight = try service.makeHighlight(
            in: book, chapter: chapter, range: 9..<19, createdAt: Date(timeIntervalSince1970: 0)
        )
        XCTAssertEqual(highlight.quotedText, "bright col")
        XCTAssertEqual(highlight.bookID, book.id)
        XCTAssertEqual(highlight.chapterID, chapter.id)
    }

    func testRangeIsClampedToChapterBounds() throws {
        let (book, chapter) = fixture()
        let highlight = try service.makeHighlight(
            in: book, chapter: chapter, range: 20..<9999, createdAt: Date(timeIntervalSince1970: 0)
        )
        XCTAssertEqual(highlight.quotedText, " day.")
        XCTAssertEqual(highlight.range.upperBound, chapter.text.count)
    }

    func testEmptySelectionThrows() {
        let (book, chapter) = fixture()
        XCTAssertThrowsError(
            try service.makeHighlight(in: book, chapter: chapter, range: 5..<5, createdAt: Date())
        ) { XCTAssertEqual($0 as? HighlightError, .emptySelection) }
    }

    func testSetNoteClearsOnEmpty() throws {
        let (book, chapter) = fixture()
        let highlight = try service.makeHighlight(
            in: book, chapter: chapter, range: 0..<2, note: "first", createdAt: Date(timeIntervalSince1970: 0)
        )
        XCTAssertEqual(service.setNote("updated", on: highlight).note, "updated")
        XCTAssertNil(service.setNote("", on: highlight).note)
    }
}
