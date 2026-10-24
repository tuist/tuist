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
            XCTAssertFalse(app.buttons["Latest messages"].exists)
            let suggestion = try app.visibleElement("Find an account", type: .button)
            XCTAssertLessThanOrEqual(suggestion.frame.maxY, app.textFields["thread-composer"].frame.minY)
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

    @MainActor func testNestedResearchToolsAndEvidence() throws {
        for dark in [false, true] {
            let app = XCUIApplication(bundleIdentifier: "dev.tuist.atlas.settings-preview")
            app.launchArguments = ["--workspace", "--orbit-tool-tree", "--destination",
                "dev.tuist.atlas://navigate/orbit/01922cc0-0000-7000-8000-000000000002?server=https%3A%2F%2Fatlas.example.org"]
                + (dark ? ["--dark", "--large-text"] : [])
            app.launch()
            let id = "thread-tool-group-01922cc0-0000-7000-8000-000000000020"
            let group = try app.visibleElement(id, type: .button)
            XCTAssertGreaterThanOrEqual(group.frame.height, 44)
            capture(app, "tool-tree-collapsed-\(dark ? "dark-large" : "light")")
            group.tap()
            let lookup = try app.visibleElement("list_error_issues · succeeded", type: .button)
            lookup.tap()
            capture(app, "tool-tree-tapped-\(dark ? "dark-large" : "light")")
            print(app.debugDescription)
            _ = try app.visibleElement("Two fixture issues, both related to indexing.")
            capture(app, "tool-tree-expanded-\(dark ? "dark-large" : "light")")
            XCTAssertTrue(app.textFields["thread-composer"].isHittable)
            app.terminate()
        }
    }

    @MainActor func testAttachmentsSendRemoveAndNativePickers() throws {
        for dark in [false, true] {
            let app = XCUIApplication(bundleIdentifier: "dev.tuist.atlas.settings-preview")
            app.launchArguments = ["--workspace", "--orbit-attachments", "--destination",
                "dev.tuist.atlas://navigate/orbit/01922cc0-0000-7000-8000-000000000001?server=https%3A%2F%2Fatlas.example.org"]
                + (dark ? ["--dark", "--large-text"] : [])
            app.launch()
            let remove = app.buttons["Remove notes.txt"]
            XCTAssertTrue(remove.waitForExistence(timeout: 10))
            XCTAssertTrue(app.buttons["thread-send"].isEnabled)
            capture(app, "attachments-draft-\(dark ? "dark-large" : "light")")
            if dark { app.buttons["thread-send"].tap() } else { remove.tap() }
            XCTAssertTrue(remove.waitForNonExistence(timeout: 5))
            XCTAssertFalse(app.buttons["thread-send"].isEnabled)
            app.buttons["thread-attach"].tap()
            XCTAssertTrue(app.buttons["Photo Library"].waitForExistence(timeout: 5))
            capture(app, "attachment-menu-\(dark ? "dark-large" : "light")")
            app.buttons["Choose Files"].tap()
            XCTAssertTrue(app.buttons["Cancel"].firstMatch.waitForExistence(timeout: 5))
            capture(app, "file-picker-\(dark ? "dark-large" : "light")")
            app.buttons["Cancel"].firstMatch.tap()
            XCTAssertTrue(app.textFields["thread-composer"].waitForExistence(timeout: 5))
            if !dark {
                let file = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "notes.txt")).firstMatch
                file.tap()
                XCTAssertTrue(app.buttons["Done"].firstMatch.waitForExistence(timeout: 5))
                XCTAssertTrue(app.navigationBars["notes.txt"].exists)
                capture(app, "attachment-preview")
                app.buttons["Done"].firstMatch.tap()
                app.buttons["thread-attach"].tap()
                app.buttons["Photo Library"].tap()
                XCTAssertTrue(app.buttons["Cancel"].firstMatch.waitForExistence(timeout: 5))
                capture(app, "photo-picker")
                app.buttons["Cancel"].firstMatch.tap()
            }
            app.terminate()
        }
    }

    @MainActor func testProfileDescriptionSaveAndFailedDraft() throws {
        for failing in [false, true] {
            let app = XCUIApplication(bundleIdentifier: "dev.tuist.atlas.settings-preview")
            app.launchArguments = ["--workspace"] + (failing ? ["--fail-business-save", "--dark", "--large-text"] : [])
            app.launch()
            XCTAssertTrue(app.tabBars.buttons["Profile"].waitForExistence(timeout: 10))
            app.tabBars.buttons["Profile"].tap()
            try app.visibleElement("profile-edit-description", type: .button).tap()
            let field = app.textViews["profile-description"]
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            field.tap()
            field.typeText("Engineering lead. Curious; concise answers please.")
            app.buttons["profile-save"].tap()
            if failing {
                XCTAssertTrue(app.staticTexts["Preview save failed. Your draft is still here."].waitForExistence(timeout: 5))
                XCTAssertTrue(app.staticTexts["Preview save failed. Your draft is still here."].isHittable)
                XCTAssertEqual(field.value as? String, "Engineering lead. Curious; concise answers please.")
                capture(app, "profile-failed-draft-dark-large")
            } else {
                XCTAssertTrue(app.buttons["profile-edit-description"].waitForExistence(timeout: 5))
                XCTAssertTrue(app.staticTexts["Engineering lead. Curious; concise answers please."].exists)
                capture(app, "profile-saved-light")
            }
            app.terminate()
        }
    }

    @MainActor func testPromptIndexLoadsEarlierAndJumpsWithoutLosingDrafts() throws {
        for (shared, dark) in [(false, false), (true, true)] {
            let app = XCUIApplication(bundleIdentifier: "dev.tuist.atlas.settings-preview")
            let thread = shared ? "01922cc0-0000-7000-8000-000000000002" : "01922cc0-0000-7000-8000-000000000001"
            app.launchArguments = ["--workspace", "--orbit-prompts", "--destination",
                "dev.tuist.atlas://navigate/orbit/\(thread)?server=https%3A%2F%2Fatlas.example.org"]
                + (dark ? ["--dark", "--large-text"] : [])
            app.launch()
            let composer = app.textFields["thread-composer"]
            XCTAssertTrue(composer.waitForExistence(timeout: 10))
            composer.tap()
            composer.typeText("Keep this draft.")
            let index = app.buttons["thread-prompts"]
            XCTAssertGreaterThanOrEqual(index.frame.height, 44)
            index.tap()
            XCTAssertTrue(app.navigationBars["Prompts"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["thread-prompt-prompt-0"].exists)
            capture(app, "prompt-index-\(dark ? "shared-dark-large" : "private-light")")
            app.buttons["Load earlier prompts"].tap()
            let first = app.buttons["thread-prompt-prompt-0"]
            XCTAssertTrue(first.waitForExistence(timeout: 5))
            XCTAssertTrue(first.label.contains("release-notes.txt"))
            XCTAssertFalse(app.buttons["Load earlier prompts"].exists)
            first.tap()
            XCTAssertTrue(app.navigationBars["Prompts"].waitForNonExistence(timeout: 5))
            let attachment = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "release-notes.txt")).firstMatch
            capture(app, "prompt-after-selection-\(dark ? "shared-dark-large" : "private-light")")
            print(app.debugDescription)
            XCTAssertTrue(attachment.waitForExistence(timeout: 5))
            XCTAssertTrue(attachment.isHittable)
            XCTAssertGreaterThanOrEqual(attachment.frame.minY, app.navigationBars.firstMatch.frame.maxY)
            XCTAssertEqual(composer.value as? String, "Keep this draft.")
            capture(app, "prompt-jump-\(dark ? "shared-dark-large" : "private-light")")
            app.buttons["Latest messages"].tap()
            XCTAssertTrue(app.staticTexts["Summarize the next steps."].isHittable)
            XCTAssertFalse(attachment.isHittable)
            XCTAssertEqual(composer.value as? String, "Keep this draft.")
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
