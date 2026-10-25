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

/// Runs against the Simulator's real photo library (PhotoKit + Vision + album export).
/// Seed first with scripts/seed-sim-photos.sh, then: scripts/test.sh -only-testing:EymraUITests/RealLibraryTest
/// with TEST_RUNNER_EYMRA_REAL_LIBRARY=1 in the environment.
final class RealLibraryTest: XCTestCase {
    @MainActor
    func testRealRunAndAlbumExport() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["EYMRA_REAL_LIBRARY"] == "1", "Set TEST_RUNNER_EYMRA_REAL_LIBRARY=1")
        let app = XCUIApplication()
        app.launch()
        // Grant photo access through the system alert if the app is asking.
        if app.buttons["allowAccess"].waitForExistence(timeout: 3) {
            app.buttons["allowAccess"].tap()
            let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            for label in ["Allow Full Access", "Allow Access to All Photos", "Allow"] {
                let button = springboard.buttons[label]
                if button.waitForExistence(timeout: 3) { button.tap(); break }
            }
        }
        let range = ProcessInfo.processInfo.environment["EYMRA_RANGE"] ?? "yesterday"
        XCTAssertTrue(app.buttons["range-\(range)"].waitForExistence(timeout: 10))
        app.buttons["range-\(range)"].tap()
        let count = app.staticTexts["photoCount"]
        XCTAssertTrue(count.waitForExistence(timeout: 10))
        let started = Date()
        app.buttons["runButton"].tap()
        XCTAssertTrue(app.staticTexts["resultsTitle"].waitForExistence(timeout: 120))
        let elapsed = Date().timeIntervalSince(started)
        let note = XCTAttachment(string: "\(count.label); run took \(String(format: "%.1f", elapsed)) s; \(app.staticTexts["resultsTitle"].label)")
        note.lifetime = .keepAlways
        add(note)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "real-results"
        shot.lifetime = .keepAlways
        add(shot)

        app.buttons["exportMenu"].tap()
        app.buttons["saveAlbum"].tap()
        let toast = app.staticTexts["toast"]
        XCTAssertTrue(toast.waitForExistence(timeout: 15))
        let saved = XCTAttachment(screenshot: app.screenshot())
        saved.name = "album-saved"
        saved.lifetime = .keepAlways
        add(saved)
        XCTAssertTrue(toast.label.hasPrefix("Saved to album"), toast.label)
    }
}
