import XCTest

/// Taps through every screen and every way in and out of it, on the bundled test photos.
/// Runs on the Simulator and on a connected iPhone.
final class EndToEndTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(_ extra: [String] = []) {
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-stillMotion"] + extra
        app.launch()
    }

    @MainActor
    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id] }

    @MainActor
    private func wait(_ id: String, _ timeout: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let e = element(id)
        XCTAssertTrue(e.waitForExistence(timeout: timeout), "\(id) never appeared", file: file, line: line)
        return e
    }

    /// Waits for an element, lets its arrival animation finish, then taps it.
    @MainActor
    private func tapWhenSettled(_ id: String, file: StaticString = #filePath, line: UInt = #line) {
        let e = wait(id, file: file, line: line)
        Thread.sleep(forTimeInterval: 0.7)
        e.tap()
    }

    @MainActor
    private func scrollTo(_ e: XCUIElement, up: Bool = true, tries: Int = 10) {
        for _ in 0..<tries where !e.isHittable { up ? app.swipeUp() : app.swipeDown() }
    }

    /// Scrolls until the element sits in the upper two-thirds of the screen, clear of the floating buttons,
    /// the way a person would before tapping it.
    @MainActor
    private func bringIntoView(_ e: XCUIElement) {
        let limit = app.frame.height * 0.62
        for _ in 0..<8 where !e.exists || e.frame.maxY > limit {
            app.swipeUp(velocity: .slow)
        }
    }

    @MainActor
    private func runToStory() {
        wait("runButton").tap()
        // The first run after a fresh install on a phone can take a while to warm up.
        _ = wait("resultsTitle", 90)
    }

    @MainActor
    private func swipeFromLeftEdge() {
        // Start right at the screen edge and move at a natural thumb speed, the way the system edge swipe expects.
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.5))
        start.press(forDuration: 0.01, thenDragTo: end, withVelocity: .default, thenHoldForDuration: 0.05)
    }

    // MARK: Onboarding

    @MainActor
    func testOnboardingForwardAndBack() {
        launch(["-onboarding", "-noGoogle"])
        wait("onboardingStart").tap()
        // Back from sign in returns to the welcome screen.
        wait("onboardingBack").tap()
        wait("onboardingStart").tap()
        let name = wait("nameField")
        name.tap()
        name.typeText("Sam")
        wait("continueWithName").tap()

        tapWhenSettled("answer-mostlyMe")
        _ = wait("answer-love")
        // Back to the first question, change the answer, go forward again.
        wait("onboardingBack").tap()
        tapWhenSettled("answer-places")
        tapWhenSettled("answer-rarely")
        tapWhenSettled("answer-bestFirst")

        _ = wait("faceSkip")
        wait("onboardingBack").tap()
        tapWhenSettled("answer-story")
        // Choosing photos of yourself opens its own screen with a back button.
        wait("faceUseUpload").tap()
        wait("faceUploadBack").tap()
        wait("faceSkip").tap()

        _ = wait("allowAccess")
        wait("onboardingBack").tap()
        wait("faceSkip").tap()
        wait("allowAccess").tap()

        _ = wait("runButton")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label ENDSWITH ', Sam'")).firstMatch.exists)
    }

    @MainActor
    func testGoogleSignInIsOffered() throws {
        launch(["-onboarding"])
        wait("onboardingStart").tap()
        // Only when this build has a Google client ID (Config/Secrets.xcconfig).
        let google = element("googleSignIn")
        if !google.waitForExistence(timeout: 5) {
            throw XCTSkip("No Google client ID in this build")
        }
        XCTAssertTrue(google.isEnabled)
        XCTAssertFalse(element("nameField").exists)
    }

    // MARK: Create

    @MainActor
    func testSetupControls() {
        launch()
        _ = wait("photoCount")
        for range in ["today", "yesterday", "last7", "custom", "last3"] {
            wait("range-\(range)").tap()
            if range == "custom" {
                XCTAssertTrue(app.datePickers.firstMatch.waitForExistence(timeout: 3), "custom range shows date pickers")
            }
        }
        XCTAssertEqual(element("photoCount").label, "40 photos from this time")

        let count = element("countValue")
        bringIntoView(count)
        wait("platform-x").tap()
        XCTAssertEqual(count.label, "4")
        XCTAssertFalse(app.buttons["More"].isEnabled, "X allows at most 4")
        app.buttons["Fewer"].tap()
        XCTAssertEqual(count.label, "3")
        wait("platform-reels").tap()
        XCTAssertEqual(count.label, "10")
        wait("platform-instagramSingle").tap()
        XCTAssertEqual(count.label, "1")
        XCTAssertFalse(app.buttons["Fewer"].isEnabled)
        wait("platform-instagramCarousel").tap()
        app.buttons["More"].tap()
        XCTAssertEqual(count.label, "11")
        app.buttons["Fewer"].tap()

        bringIntoView(app.buttons["More of me"])
        for focus in ["More of me", "More places", "A mix"] {
            app.buttons[focus].tap()
            XCTAssertTrue(app.buttons[focus].isSelected, "\(focus) selected")
        }
    }

    @MainActor
    func testEveryWayBackFromTheStory() {
        launch()
        runToStory()
        // The back button.
        wait("resultsBack").tap()
        // The last story card brings it back.
        wait("lastStoryCard").tap()
        _ = wait("resultsTitle")
        // Swiping from the left edge goes back too.
        swipeFromLeftEdge()
        XCTAssertTrue(wait("lastStoryCard").exists)
        // And the Stories tab opens it.
        wait("tab-stories").tap()
        wait("storyRow-0").tap()
        _ = wait("resultsTitle")
        wait("resultsBack").tap()
        XCTAssertTrue(wait("runButton").exists)
    }

    @MainActor
    func testStopWhileWorking() {
        launch(["-slowRun"])
        wait("runButton").tap()
        let stop = app.buttons["cancelRun"]
        XCTAssertTrue(stop.waitForExistence(timeout: 5), "Stop shows while working")
        stop.tap()
        XCTAssertTrue(wait("runButton").exists)
        XCTAssertFalse(element("resultsTitle").exists)
    }

    // MARK: A photo

    @MainActor
    func testPhotoDetail() {
        launch()
        runToStory()

        // Keep it, copy it, close with Done.
        wait("pick-1").tap()
        let lock = wait("lockButton")
        scrollTo(lock)
        lock.tap()
        XCTAssertTrue(app.buttons["Unlock"].waitForExistence(timeout: 3))
        wait("copyForStory").tap()
        XCTAssertTrue(wait("toast", 5).label.hasPrefix("Copied"), "the copy message shows on the photo screen")
        let done = wait("detailDone")
        scrollTo(done, up: false)
        done.tap()
        _ = wait("resultsTitle")

        // Pull the photo down to close (after the zoom-out has finished).
        Thread.sleep(forTimeInterval: 1)
        wait("pick-1").tap()
        let photo = wait("detailPhoto")
        photo.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)))
        _ = wait("resultsTitle")
        XCTAssertFalse(element("detailPhoto").exists)

        // Use a runner-up instead.
        Thread.sleep(forTimeInterval: 1)
        wait("pick-1").tap()
        let runnerUp = app.buttons["runnerUp"].firstMatch
        if runnerUp.waitForExistence(timeout: 3) {
            scrollTo(runnerUp)
            runnerUp.tap()
            _ = wait("resultsTitle")
        } else {
            wait("detailDone").tap()
        }
    }

    @MainActor
    func testHideAPhoto() {
        launch()
        runToStory()
        wait("pick-2").tap()
        let hide = wait("hidePhoto")
        scrollTo(hide)
        hide.tap()
        let confirm = app.buttons["Hide and pick again"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        confirm.tap()
        _ = wait("resultsTitle", 40)
        XCTAssertTrue(element("pick-1").exists)
    }

    // MARK: Other photos and the menu

    @MainActor
    func testOtherPhotosAndWhyNot() {
        launch()
        runToStory()
        let section = wait("excludedSection")
        scrollTo(section)
        section.tap()
        app.swipeUp()
        let why = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'almost the same' OR label CONTAINS[c] 'missed out' OR label CONTAINS[c] 'same spot'")).firstMatch
        XCTAssertTrue(why.waitForExistence(timeout: 5))
        why.tap()
        _ = wait("whyNotReason")
        wait("whyNotClose").tap()
        why.tap()
        if element("swapIn").waitForExistence(timeout: 3) { element("swapIn").tap() } else { wait("whyNotClose").tap() }
        _ = wait("resultsTitle")
        // Collapse it again.
        scrollTo(section)
        section.tap()
    }

    @MainActor
    func testMenuPickAgainAndShare() {
        launch()
        runToStory()
        wait("moreMenu").tap()
        app.buttons["Pick again (keep the ones I locked)"].tap()
        _ = wait("resultsTitle", 40)

        wait("moreMenu").tap()
        app.buttons["Share all"].tap()
        // The system share sheet appears; close it.
        let shareSheet = app.otherElements["ActivityListView"]
        let close = app.buttons["Close"]
        XCTAssertTrue(shareSheet.waitForExistence(timeout: 15) || close.waitForExistence(timeout: 1), "share sheet appears")
        if close.exists { close.tap() } else { app.swipeDown(velocity: .fast) }
        _ = wait("resultsTitle")
    }

    // MARK: You

    @MainActor
    func testProfile() {
        launch()
        wait("tab-you").tap()

        // Your style menus (their labels include the current answer).
        let style = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'I mostly post'")).firstMatch
        XCTAssertTrue(style.waitForExistence(timeout: 5))
        style.tap()
        app.buttons["Mostly me"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label == 'I mostly post, Mostly me'")).firstMatch.waitForExistence(timeout: 3))

        // Deeper picks: turn on, save a key, remove it.
        let toggle = wait("judgeToggle")
        scrollTo(toggle)
        toggle.switches.firstMatch.exists ? toggle.switches.firstMatch.tap() : toggle.tap()
        let field = wait("apiKeyField")
        bringIntoView(field)
        field.tap()
        // Wait for the keyboard before typing.
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "keyboard opens for the key field")
        // Done on the keyboard saves the key.
        field.typeText("sk-ant-test-key\n")
        XCTAssertTrue(app.staticTexts["Your key is saved"].waitForExistence(timeout: 3))
        wait("removeKey").tap()
        XCTAssertTrue(app.staticTexts["Paste your Anthropic API key"].waitForExistence(timeout: 3))

        // Face photos screen opens and closes.
        app.swipeDown()
        app.swipeDown()
        wait("faceChoosePhotos").tap()
        wait("faceUploadBack").tap()

        // Photos and privacy buttons.
        let hidden = app.buttons["Show hidden photos again"]
        scrollTo(hidden)
        hidden.tap()
        XCTAssertTrue(app.staticTexts["Hidden photos are back."].waitForExistence(timeout: 3))

        // Sign out returns to onboarding.
        let signOut = wait("signOut")
        scrollTo(signOut)
        signOut.tap()
        app.buttons.matching(NSPredicate(format: "label == 'Sign out'")).element(boundBy: 1).tap()
        XCTAssertTrue(wait("onboardingStart").exists)
    }

    @MainActor
    func testIsThisYou() {
        launch()
        runToStory()
        let card = wait("faceCheckCard")
        card.tap()
        let me = app.buttons["faceMe"].firstMatch
        XCTAssertTrue(me.waitForExistence(timeout: 5))
        me.tap()
        wait("faceCheckSave").tap()
        // Eymra picks again with the answer (the old story leaves first); the face is now sure, so nothing is left to ask.
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: element("faceCheckCard"))
        wait(for: [gone], timeout: 90)
        _ = wait("resultsTitle", 90)
        // And Eymra still knows who you are (the answer was added, nothing was lost).
        XCTAssertEqual(element("resultsTitle").value as? String, "Found you")
    }

    @MainActor
    func testTabsKeepTheirState() {
        launch()
        wait("platform-x").tap()
        wait("tab-stories").tap()
        wait("tab-you").tap()
        wait("tab-create").tap()
        XCTAssertEqual(element("countValue").label, "4", "Create kept its settings across tabs")
    }
}
