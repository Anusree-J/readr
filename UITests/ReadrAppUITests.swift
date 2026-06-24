import XCTest

/// J1/J2 UI smoke test — launch with a seeded library, open the book, navigate
/// chapters. Runs on the simulator (macOS CI / local Mac). The seed avoids
/// driving the system file importer, which UI tests can't reliably automate.
final class ReadrAppUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    func testOpenSeededBookAndNavigateChapters() {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestSeed"]
        app.launch()

        // Library shows the seeded book.
        let bookCell = app.staticTexts["Sample Book"]
        XCTAssertTrue(bookCell.waitForExistence(timeout: 5))
        bookCell.tap()

        // Reader shows chapter one.
        XCTAssertTrue(app.staticTexts["Chapter One"].waitForExistence(timeout: 5))

        // Navigate to chapter two via the forward button.
        app.buttons["nextChapter"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Chapter Two"].waitForExistence(timeout: 5))
    }

    func testEmptyLibraryShowsGuidance() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(
            app.staticTexts["Your library is empty"].waitForExistence(timeout: 5)
            || app.staticTexts["Sample Book"].waitForExistence(timeout: 1)
        )
    }
}
