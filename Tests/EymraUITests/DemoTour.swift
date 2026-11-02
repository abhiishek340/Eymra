import XCTest

/// Walks the whole app at a watchable pace, for recording a demo video on a Simulator seeded with a real trip.
/// Skipped unless TEST_RUNNER_EYMRA_DEMO=1; scripts/record-demo.sh sets everything up and records it.
final class DemoTour: XCTestCase {
    private var app: XCUIApplication!

    @MainActor
    func testTour() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["EYMRA_DEMO"] == "1", "Set TEST_RUNNER_EYMRA_DEMO=1")
        app = XCUIApplication()
        app.launchArguments = ["-noGoogle"]
        app.launch()

        // Welcome: let the photos fly in, line up, ring the name and open into the arc.
        XCTAssertTrue(app.buttons["onboardingStart"].waitForExistence(timeout: 15))
        pause(6)
        app.buttons["onboardingStart"].tap()
        pause(1.2)

        let name = app.textFields["nameField"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Maya")
        pause(0.6)
        app.buttons["continueWithName"].tap()
        pause(1.4)

        for answer in ["answer-mix", "answer-love", "answer-story"] {
            XCTAssertTrue(app.buttons[answer].waitForExistence(timeout: 5))
            pause(1.1)
            app.buttons[answer].tap()
            pause(0.9)
        }
        XCTAssertTrue(app.buttons["faceSkip"].waitForExistence(timeout: 5))
        pause(1.5)
        app.buttons["faceSkip"].tap()
        XCTAssertTrue(app.buttons["allowAccess"].waitForExistence(timeout: 5))
        pause(2.5)
        app.buttons["allowAccess"].tap()

        // Create: the ring, the backdrop, then the choices.
        XCTAssertTrue(app.buttons["runButton"].waitForExistence(timeout: 15))
        pause(7)
        scroll(up: true)
        pause(1)
        app.buttons["range-last3"].tap()
        pause(2)
        scroll(up: true)
        pause(2.5)
        scroll(up: false)
        scroll(up: false)
        pause(3)
        app.buttons["runButton"].tap()

        // Working, then the story.
        XCTAssertTrue(app.descendants(matching: .any)["resultsTitle"].waitForExistence(timeout: 240))
        pause(4)
        for _ in 0..<3 {
            scroll(up: true)
            pause(1.8)
        }
        scroll(up: false)
        scroll(up: false)
        scroll(up: false)
        pause(1.5)
        app.buttons["pick-1"].tap()
        pause(4)
        app.swipeDown(velocity: .slow)
        pause(2)

        // Back to Create, then Stories and You.
        app.buttons["resultsBack"].tap()
        pause(2.5)
        app.buttons["tab-stories"].tap()
        pause(4)
        app.buttons["tab-you"].tap()
        pause(3)
        scroll(up: true)
        pause(2.5)
        app.buttons["tab-create"].tap()
        pause(5)
    }

    private func pause(_ seconds: Double) {
        Thread.sleep(forTimeInterval: seconds)
    }

    /// A slow, human scroll of about a third of the screen.
    @MainActor
    private func scroll(up: Bool) {
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.7 : 0.35))
        let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.35 : 0.7))
        from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.1)
    }
}
