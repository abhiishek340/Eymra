import XCTest

/// Drives the app on the fixture set and keeps a screenshot of every screen.
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
    func testOnboarding() throws {
        let app = launch(["-onboarding", "-noGoogle"])
        XCTAssertTrue(app.buttons["onboardingStart"].waitForExistence(timeout: 10))
        sleep(2)
        screenshot(app, "01-welcome")
        app.buttons["onboardingStart"].tap()

        // Google isn't configured in test builds, so the name path shows.
        let name = app.textFields["nameField"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        screenshot(app, "02-sign-in")
        name.tap()
        name.typeText("Alex")
        app.buttons["continueWithName"].tap()

        XCTAssertTrue(app.buttons["answer-mostlyMe"].waitForExistence(timeout: 5))
        screenshot(app, "03-question-1")
        app.buttons["answer-meAndFriends"].tap()
        XCTAssertTrue(app.buttons["answer-love"].waitForExistence(timeout: 5))
        screenshot(app, "04-question-2")
        app.buttons["answer-love"].tap()
        XCTAssertTrue(app.buttons["answer-story"].waitForExistence(timeout: 5))
        app.buttons["answer-story"].tap()

        XCTAssertTrue(app.buttons["faceSkip"].waitForExistence(timeout: 5))
        screenshot(app, "05-face-intro")
        app.buttons["faceSkip"].tap()

        XCTAssertTrue(app.buttons["allowAccess"].waitForExistence(timeout: 5))
        screenshot(app, "06-photo-access")
        app.buttons["allowAccess"].tap()

        XCTAssertTrue(app.buttons["runButton"].waitForExistence(timeout: 10))
        let greeting = app.staticTexts.matching(NSPredicate(format: "label ENDSWITH ', Alex'")).firstMatch
        XCTAssertTrue(greeting.exists)
    }

    @MainActor
    func testRunShowsTenPicksAndEditing() throws {
        let app = launch()
        XCTAssertTrue(app.descendants(matching: .any)["photoCount"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.descendants(matching: .any)["photoCount"].label, "40 photos from this time")
        sleep(1)
        screenshot(app, "10-home")

        app.buttons["runButton"].tap()
        // The working state is constantly animating (and short with 40 photos), so it's photographed, not queried.
        Thread.sleep(forTimeInterval: 0.9)
        screenshot(app, "10b-working")
        XCTAssertTrue(app.descendants(matching: .any)["resultsTitle"].waitForExistence(timeout: 30))
        XCTAssertEqual(app.descendants(matching: .any)["resultsTitle"].label, "10 photos, picked from 40")
        sleep(2)
        screenshot(app, "11-results")
        app.swipeUp()
        screenshot(app, "12-results-scrolled")
        app.swipeDown()
        app.swipeDown()

        // Photo detail: keep it.
        app.buttons["pick-1"].tap()
        let lock = app.buttons["lockButton"]
        XCTAssertTrue(lock.waitForExistence(timeout: 5))
        sleep(1)
        screenshot(app, "13-detail")
        for _ in 0..<5 where !lock.isHittable { app.swipeUp() }
        lock.tap()
        XCTAssertTrue(app.buttons["Unlock"].waitForExistence(timeout: 5))
        let done = app.buttons["detailDone"]
        for _ in 0..<5 where !done.isHittable { app.swipeDown() }
        done.tap()
        XCTAssertTrue(app.descendants(matching: .any)["resultsTitle"].waitForExistence(timeout: 5))

        // Other photos → why not → use it instead.
        let excluded = app.buttons["excludedSection"]
        for _ in 0..<12 where !excluded.isHittable { app.swipeUp() }
        excluded.tap()
        app.swipeUp()
        screenshot(app, "14-other-photos")
        let firstWhyNot = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'almost the same' OR label CONTAINS[c] 'missed out' OR label CONTAINS[c] 'same spot'")).firstMatch
        XCTAssertTrue(firstWhyNot.waitForExistence(timeout: 5))
        firstWhyNot.tap()
        XCTAssertTrue(app.staticTexts["whyNotReason"].waitForExistence(timeout: 5))
        sleep(1)
        screenshot(app, "15-why-not")
        if app.buttons["swapIn"].exists { app.buttons["swapIn"].tap() } else { app.buttons["whyNotClose"].tap() }
        XCTAssertTrue(app.descendants(matching: .any)["resultsTitle"].waitForExistence(timeout: 5))

        // Back home, then the Stories and You tabs.
        app.buttons["resultsBack"].tap()
        XCTAssertTrue(app.buttons["tab-stories"].waitForExistence(timeout: 5))
        app.buttons["tab-stories"].tap()
        sleep(1)
        screenshot(app, "16-stories")
        app.buttons["tab-you"].tap()
        XCTAssertTrue(app.switches["judgeToggle"].waitForExistence(timeout: 5))
        sleep(1)
        screenshot(app, "17-you")
    }

    @MainActor
    func testClaudePathWithStub() throws {
        let app = launch(["-judge"])
        XCTAssertTrue(app.buttons["runButton"].waitForExistence(timeout: 10))
        app.buttons["runButton"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["resultsTitle"].waitForExistence(timeout: 30))
        XCTAssertEqual(app.staticTexts["storyTitle"].label, "A golden day out")
        // Nothing on the story says how it was made.
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] 'Claude'")).firstMatch.exists)
        screenshot(app, "20-results-claude")
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
        // Walk onboarding if this is a fresh install.
        if app.buttons["onboardingStart"].waitForExistence(timeout: 3) {
            app.buttons["onboardingStart"].tap()
            if app.textFields["nameField"].waitForExistence(timeout: 3) {
                app.textFields["nameField"].tap()
                app.textFields["nameField"].typeText("Tester")
                app.buttons["continueWithName"].tap()
            }
            for answer in ["answer-mix", "answer-sometimes", "answer-story"] {
                if app.buttons[answer].waitForExistence(timeout: 3) { app.buttons[answer].tap() }
            }
            if app.buttons["faceSkip"].waitForExistence(timeout: 3) { app.buttons["faceSkip"].tap() }
            if app.buttons["allowAccess"].waitForExistence(timeout: 3) {
                app.buttons["allowAccess"].tap()
                let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
                for label in ["Allow Full Access", "Allow Access to All Photos", "Allow"] {
                    let button = springboard.buttons[label]
                    if button.waitForExistence(timeout: 3) { button.tap(); break }
                }
            }
        }
        let range = ProcessInfo.processInfo.environment["EYMRA_RANGE"] ?? "yesterday"
        XCTAssertTrue(app.buttons["range-\(range)"].waitForExistence(timeout: 10))
        app.buttons["range-\(range)"].tap()
        let count = app.descendants(matching: .any)["photoCount"]
        XCTAssertTrue(count.waitForExistence(timeout: 10))
        let started = Date()
        app.buttons["runButton"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["resultsTitle"].waitForExistence(timeout: 120))
        let elapsed = Date().timeIntervalSince(started)
        let note = XCTAttachment(string: "\(count.label); run took \(String(format: "%.1f", elapsed)) s; \(app.descendants(matching: .any)["resultsTitle"].label)")
        note.lifetime = .keepAlways
        add(note)

        app.buttons["saveAlbum"].tap()
        let toast = app.staticTexts["toast"]
        XCTAssertTrue(toast.waitForExistence(timeout: 15))
        let saved = XCTAttachment(screenshot: app.screenshot())
        saved.name = "album-saved"
        saved.lifetime = .keepAlways
        add(saved)
        XCTAssertTrue(toast.label.hasPrefix("Saved to your Photos"), toast.label)
    }
}
