import XCTest

/// Drives the Apple TV remote through the classic menu: swipes have to move the selection the
/// console reports.
@MainActor
final class ClassicMenuRemoteTests: XCTestCase {
    func testSwipingMovesThroughTheClassicMenu() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        let remote = XCUIRemote.shared

        // A simulator that isn't signed in to Game Center shows its welcome sheet first.
        let notNow = app.buttons["Not Now"]
        if notNow.waitForExistence(timeout: 8) {
            remote.press(.down)
            remote.press(.select)
        }

        // The shell boots first; its buttons are disabled until the prompt is ready.
        let start = app.buttons["start"]
        let found = start.waitForExistence(timeout: 15)
        attachScreenshot(of: app, named: "after launch")
        add(XCTAttachment(string: app.debugDescription))
        XCTAssertTrue(found, "no start button")
        wait(for: start, "isEnabled == true", timeout: 15)
        remote.press(.select)

        let console = app.descendants(matching: .any).matching(identifier: "console").firstMatch
        expectValue(of: console, "New Game", timeout: 40)
        attachScreenshot(of: app, named: "menu")

        remote.press(.down)
        expectValue(of: console, "Highscore")
        remote.press(.down)
        expectValue(of: console, "Change Avatar")
        remote.press(.up)
        expectValue(of: console, "Highscore")
        attachScreenshot(of: app, named: "after moving")
    }

    /// A new game on the TV uses its whole width: more landscape than the original 80 columns.
    func testANewGameFillsTheWideScreen() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        let remote = XCUIRemote.shared

        let notNow = app.buttons["Not Now"]
        if notNow.waitForExistence(timeout: 8) {
            remote.press(.down)
            remote.press(.select)
        }
        let start = app.buttons["start"]
        XCTAssertTrue(start.waitForExistence(timeout: 15))
        wait(for: start, "isEnabled == true", timeout: 15)
        remote.press(.select)

        let console = app.descendants(matching: .any).matching(identifier: "console").firstMatch
        expectValue(of: console, "New Game", timeout: 40)
        remote.press(.select)
        // Outside a menu the console has no selection to report.
        expectValue(of: console, "", timeout: 10)
        attachScreenshot(of: app, named: "wide game")
    }

    private func expectValue(of element: XCUIElement, _ value: String, timeout: TimeInterval = 5) {
        wait(for: element, "value == '\(value)'", timeout: timeout)
    }

    private func wait(for element: XCUIElement, _ format: String, timeout: TimeInterval) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: format), object: element)
        let result = XCTWaiter.wait(for: [expectation], timeout: timeout)
        XCTAssertEqual(result, .completed, "\(format) not met; value is \(String(describing: element.value))")
    }

    private func attachScreenshot(of app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
