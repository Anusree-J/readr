import XCTest
@testable import ReadrKit

/// Regression tests for M1 (launch readiness): EPUB zip-bomb / unbounded
/// extraction. Verifies the per-entry, cumulative, and spine-count ceilings
/// and that they equal the documented values.
final class ReviewFixesM1ExtractionCapsTests: XCTestCase {

    // MARK: Named constants match the documented limits

    func testExtractionLimitConstantsMatchDocumentedValues() {
        XCTAssertEqual(EPUBExtractionLimits.perEntryByteCap, 64 * 1024 * 1024)
        XCTAssertEqual(EPUBExtractionLimits.cumulativeByteCap, 512 * 1024 * 1024)
        XCTAssertEqual(EPUBBookParser.maxSpineItems, 2000)
    }

    func testBudgetDefaultsToDocumentedLimits() {
        let budget = EPUBExtractionBudget()
        XCTAssertEqual(budget.perEntryByteCap, 64 * 1024 * 1024)
        XCTAssertEqual(budget.cumulativeByteCap, 512 * 1024 * 1024)
    }

    // MARK: Per-entry cap

    func testOversizedSingleEntryThrows() {
        // Small, cheap-to-run caps so we don't allocate real megabytes.
        let budget = EPUBExtractionBudget(perEntryByteCap: 1024, cumulativeByteCap: 1_000_000)
        let container = InMemoryEPUBContainer(
            entries: ["big.bin": Data(count: 1025)],
            extractionBudget: budget
        )
        XCTAssertThrowsError(try container.data(at: "big.bin")) { error in
            guard case EPUBParseError.entryTooLarge(let path, let limit) = error else {
                return XCTFail("expected entryTooLarge, got \(error)")
            }
            XCTAssertEqual(path, "big.bin")
            XCTAssertEqual(limit, 1024)
        }
    }

    // MARK: Cumulative cap

    func testCumulativeOverflowThrows() {
        // Each entry is under the per-entry cap, but together they exceed the
        // shared cumulative cap.
        let budget = EPUBExtractionBudget(perEntryByteCap: 1024, cumulativeByteCap: 1536)
        let container = InMemoryEPUBContainer(
            entries: ["a.bin": Data(count: 1000), "b.bin": Data(count: 1000)],
            extractionBudget: budget
        )
        XCTAssertNoThrow(try container.data(at: "a.bin"))
        XCTAssertThrowsError(try container.data(at: "b.bin")) { error in
            guard case EPUBParseError.cumulativeSizeExceeded(let limit) = error else {
                return XCTFail("expected cumulativeSizeExceeded, got \(error)")
            }
            XCTAssertEqual(limit, 1536)
        }
    }

    // MARK: Under-cap succeeds

    func testUnderCapEntriesExtractSuccessfully() throws {
        let budget = EPUBExtractionBudget(perEntryByteCap: 1024, cumulativeByteCap: 4096)
        let container = InMemoryEPUBContainer(
            entries: ["a.bin": Data(count: 500), "b.bin": Data(count: 500)],
            extractionBudget: budget
        )
        XCTAssertEqual(try container.data(at: "a.bin").count, 500)
        XCTAssertEqual(try container.data(at: "b.bin").count, 500)
        XCTAssertEqual(budget.cumulativeBytes, 1000)
    }

    // MARK: Spine-count ceiling

    func testSpineOverCeilingThrows() {
        let overflow = EPUBBookParser.maxSpineItems + 1
        var manifest = ""
        var spine = ""
        for i in 0..<overflow {
            manifest += "<item id=\"c\(i)\" href=\"c\(i).xhtml\" media-type=\"application/xhtml+xml\"/>"
            spine += "<itemref idref=\"c\(i)\"/>"
        }
        var textEntries: [String: String] = [
            "META-INF/container.xml": """
            <?xml version="1.0"?>
            <container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0">
              <rootfiles><rootfile full-path="content.opf" media-type="application/oebps-package+xml"/></rootfiles>
            </container>
            """,
            "content.opf": """
            <?xml version="1.0"?>
            <package xmlns="http://www.idpf.org/2007/opf" version="3.0">
              <metadata/>
              <manifest>\(manifest)</manifest>
              <spine>\(spine)</spine>
            </package>
            """,
        ]
        for i in 0..<overflow {
            textEntries["c\(i).xhtml"] = "<html><body><p>c\(i)</p></body></html>"
        }
        let container = InMemoryEPUBContainer(textEntries: textEntries)
        XCTAssertThrowsError(
            try EPUBBookParser().parse(container: container, fallbackTitle: "fallback")
        ) { error in
            guard case EPUBParseError.tooManySpineItems(let count, let limit) = error else {
                return XCTFail("expected tooManySpineItems, got \(error)")
            }
            XCTAssertEqual(count, overflow)
            XCTAssertEqual(limit, EPUBBookParser.maxSpineItems)
        }
    }

    // MARK: A book at the spine ceiling still parses

    func testSpineAtCeilingParses() throws {
        let count = EPUBBookParser.maxSpineItems
        var manifest = ""
        var spine = ""
        for i in 0..<count {
            manifest += "<item id=\"c\(i)\" href=\"c\(i).xhtml\" media-type=\"application/xhtml+xml\"/>"
            spine += "<itemref idref=\"c\(i)\"/>"
        }
        var textEntries: [String: String] = [
            "META-INF/container.xml": """
            <?xml version="1.0"?>
            <container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0">
              <rootfiles><rootfile full-path="content.opf" media-type="application/oebps-package+xml"/></rootfiles>
            </container>
            """,
            "content.opf": """
            <?xml version="1.0"?>
            <package xmlns="http://www.idpf.org/2007/opf" version="3.0">
              <metadata/>
              <manifest>\(manifest)</manifest>
              <spine>\(spine)</spine>
            </package>
            """,
        ]
        for i in 0..<count {
            textEntries["c\(i).xhtml"] = "<html><body><p>c\(i)</p></body></html>"
        }
        let container = InMemoryEPUBContainer(textEntries: textEntries)
        let book = try EPUBBookParser().parse(container: container, fallbackTitle: "fallback")
        XCTAssertEqual(book.chapters.count, count)
    }
}
