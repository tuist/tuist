import XCTest

/// Temporary, offline native validation. Removed before final PR delivery.
final class AtlasRenderValidation: XCTestCase {
    @MainActor func testWelcomeReactionsAndSuggestedDraft() throws {
        let app = XCUIApplication(bundleIdentifier: "dev.tuist.atlas.settings-preview")
        app.launchArguments = ["--workspace"]
        app.launch()
        defer { app.terminate() }
        XCUIDevice.shared.orientation = .portrait
        let pip = app.buttons["pip-mascot"]
        XCTAssertTrue(pip.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["orbit-private"].isHittable)
        XCTAssertGreaterThanOrEqual(pip.frame.height, 44)
        capture(app, "home-light")
        pip.tap()
        XCTAssertEqual(pip.value as? String, "Waving hello")
        pip.press(forDuration: 0.9)
        XCTAssertEqual(pip.value as? String, "Sending a little love")
        capture(app, "home-reaction")
        try app.visibleElement("Summarize my open tasks").tap()
        let composer = app.textFields["thread-composer"]
        XCTAssertTrue(composer.waitForExistence(timeout: 10))
        XCTAssertEqual(composer.value as? String, "Summarize my open tasks")
        XCTAssertFalse(app.tabBars.firstMatch.isHittable)
        capture(app, "suggested-draft")
    }

    @MainActor func testVoiceHoldStopReviewAcceptAndCancel() throws {
        let app = XCUIApplication(bundleIdentifier: "dev.tuist.atlas.settings-preview")
        app.launchArguments = ["--voice-input"]
        app.launch()
        defer { app.terminate() }
        let microphone = app.buttons["thread-microphone"]
        XCTAssertTrue(microphone.waitForExistence(timeout: 10))
        XCTAssertEqual(microphone.frame.width, 44, accuracy: 1)
        XCTAssertEqual(app.buttons["thread-voice-done"].frame.height, 44, accuracy: 1)
        capture(app, "voice-recording")
        app.buttons["thread-voice-cancel"].tap()
        XCTAssertEqual(app.textFields["thread-composer"].value as? String, "Existing draft.")
        microphone.press(forDuration: 1)
        XCTAssertTrue(app.staticTexts["Review your transcript"].waitForExistence(timeout: 5))
        capture(app, "voice-review")
        app.buttons["thread-voice-cancel"].tap()
        XCTAssertEqual(app.textFields["thread-composer"].value as? String, "Existing draft.")
        microphone.tap()
        XCTAssertTrue(app.staticTexts["Transcribing on this device"].waitForExistence(timeout: 5))
        microphone.tap()
        XCTAssertTrue(app.staticTexts["Review your transcript"].waitForExistence(timeout: 5))
        app.buttons["thread-voice-done"].tap()
        XCTAssertEqual(app.textFields["thread-composer"].value as? String, "Existing draft. Compare the latest build timings.")
        capture(app, "voice-accepted-draft")
    }

    @MainActor func testComposerWithKeyboardAndLargeDarkText() throws {
        for dark in [false, true] {
            let app = XCUIApplication(bundleIdentifier: "dev.tuist.atlas.settings-preview")
            app.launchArguments = ["--voice-input", "--text-composer", "--typing-preview"] + (dark ? ["--dark", "--large-text"] : [])
            app.launch()
            let composer = app.textFields["thread-composer"]
            XCTAssertTrue(composer.waitForExistence(timeout: 10))
            capture(app, "text-typing-\(dark ? "dark-large" : "light")")
            composer.tap()
            composer.typeText("\nInclude recent activity.")
            let send = app.buttons["thread-send"]
            let microphone = app.buttons["thread-microphone"]
            XCTAssertEqual(send.frame.height, 44, accuracy: 1)
            XCTAssertEqual(send.frame.midY, microphone.frame.midY, accuracy: 1)
            XCTAssertTrue(send.isHittable)
            XCTAssertLessThanOrEqual(send.frame.maxY, app.keyboards.firstMatch.frame.minY)
            capture(app, "text-keyboard-\(dark ? "dark-large" : "light")")
            app.terminate()
        }
    }

    @MainActor func testOrbitNotificationLinkAndEmptyWelcome() throws {
        for dark in [false, true] {
            let app = XCUIApplication(bundleIdentifier: "dev.tuist.atlas.settings-preview")
            app.launchArguments = ["--workspace", "--empty-private", "--destination",
                "dev.tuist.atlas://navigate/orbit/01922cc0-0000-7000-8000-000000000001?server=https%3A%2F%2Fatlas.example.org"]
                + (dark ? ["--dark", "--large-text"] : [])
            app.launch()
            XCTAssertTrue(app.textFields["thread-composer"].waitForExistence(timeout: 10))
            XCTAssertTrue(app.navigationBars["Pip"].exists)
            XCTAssertFalse(app.tabBars.firstMatch.isHittable)
            capture(app, "empty-thread-\(dark ? "dark-large" : "light")")
            app.navigationBars.buttons.element(boundBy: 0).tap()
            XCTAssertTrue(app.buttons["orbit-private"].waitForExistence(timeout: 5))
            capture(app, "home-\(dark ? "dark-large" : "light")")
            app.tabBars.buttons["Accounts"].tap()
            app.tabBars.buttons["Orbit"].tap()
            XCTAssertTrue(app.navigationBars["Orbit"].exists)
            app.terminate()
        }
    }

    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
