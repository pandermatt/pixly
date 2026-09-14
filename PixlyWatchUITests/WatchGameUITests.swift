import XCTest

/// Plays one run on the watch: a tap starts the game, no more taps crash it, and the score shows.
@MainActor
final class WatchGameUITests: XCTestCase {
    func testATapStartsTheGameAndACrashShowsTheScore() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.staticTexts["tap to start"].waitForExistence(timeout: 30), "no start hint")
        attachScreenshot(of: app, named: "ready")

        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6)).tap()
        attachScreenshot(of: app, named: "playing")

        // Without more jumps the pixel drops into the wall within a few seconds.
        XCTAssertTrue(app.staticTexts["GAME OVER"].waitForExistence(timeout: 20), "the run didn't end")
        XCTAssertTrue(app.staticTexts["tap to play again"].waitForExistence(timeout: 5), "no restart hint")
        attachScreenshot(of: app, named: "game over")
    }

    private func attachScreenshot(of app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
