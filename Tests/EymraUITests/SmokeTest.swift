import XCTest

/// Drives the whole flow on the fixture set: run → results → pick detail → lock → "Why not?" → swap in.
final class SmokeTest: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"] + extra
        app.launch()
        return app
    }

    @MainActor
    private func screenshot(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    @MainActor
    func testRunShowsTenPicksAndEditing() throws {
        let app = launch()
        XCTAssertTrue(app.staticTexts["photoCount"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["photoCount"].label, "40 photos in this range")
        screenshot(app, "1-home")

        app.buttons["runButton"].tap()
        XCTAssertTrue(app.staticTexts["resultsTitle"].waitForExistence(timeout: 30))
        XCTAssertEqual(app.staticTexts["resultsTitle"].label, "10 keepers")
        screenshot(app, "2-results")

        // Pick detail: lock it.
        app.buttons["pick-1"].tap()
        XCTAssertTrue(app.navigationBars["Pick 1"].waitForExistence(timeout: 5))
        screenshot(app, "3-pick-detail")
        let lock = app.buttons["lockButton"]
        for _ in 0..<5 where !lock.isHittable { app.swipeUp() }
        XCTAssertEqual(lock.label, "Lock (keep on re-run)")
        lock.tap()
        XCTAssertTrue(app.buttons["Unlock"].waitForExistence(timeout: 5))
        app.navigationBars["Pick 1"].buttons["Done"].tap()
        XCTAssertTrue(app.buttons["pick-1"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["pick-1"].images["lock.fill"].exists || app.images["lock.fill"].exists)

        // Everything else → Why not? → swap in.
        let excluded = app.buttons["excludedSection"]
        for _ in 0..<8 where !excluded.isHittable { app.swipeUp() }
        excluded.tap()
        app.swipeUp()
        let firstWhyNot = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'near-duplicate' OR label CONTAINS[c] 'ranked' OR label CONTAINS[c] 'background'")).firstMatch
        XCTAssertTrue(firstWhyNot.waitForExistence(timeout: 5))
        firstWhyNot.tap()
        XCTAssertTrue(app.staticTexts["whyNotReason"].waitForExistence(timeout: 5))
        screenshot(app, "4-why-not")
        if app.buttons["swapIn"].exists {
            app.buttons["swapIn"].tap()
        } else {
            app.buttons["Done"].firstMatch.tap()
        }
        XCTAssertTrue(app.staticTexts["resultsTitle"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["resultsTitle"].label, "10 keepers")
    }

    @MainActor
    func testJudgePathWithStub() throws {
        let app = launch(["-judge"])
        XCTAssertTrue(app.buttons["runButton"].waitForExistence(timeout: 10))
        app.buttons["runButton"].tap()
        XCTAssertTrue(app.staticTexts["resultsTitle"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts["AI Judge used"].exists)
        screenshot(app, "5-results-judge")
    }

    @MainActor
    func testSettingsOpens() throws {
        let app = launch()
        app.buttons["settingsButton"].tap()
        XCTAssertTrue(app.switches["judgeToggle"].waitForExistence(timeout: 5))
        screenshot(app, "6-settings")
        app.buttons["settingsDone"].tap()
        XCTAssertTrue(app.buttons["runButton"].waitForExistence(timeout: 5))
    }
}
