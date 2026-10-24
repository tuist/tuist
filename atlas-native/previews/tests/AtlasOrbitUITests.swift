import XCTest

final class AtlasOrbitUITests: XCTestCase {
    @MainActor func testPrivateThreadAndSharedToolEvidence() throws {
        let app = XCUIApplication(bundleIdentifier: "dev.tuist.atlas.settings-preview")
        app.launchArguments = ["--workspace"]
        app.launch()
        defer { app.terminate() }
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(app.navigationBars["Orbit"].waitForExistence(timeout: 10))
        let privateThread = app.buttons["orbit-private"]
        XCTAssertTrue(privateThread.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(privateThread.frame.height, 44)
        capture(app, "ios-orbit-list-preview")
        privateThread.tap()
        XCTAssertTrue(app.navigationBars["Pip"].waitForExistence(timeout: 5))
        let composer = app.textFields["thread-composer"]
        XCTAssertTrue(composer.waitForExistence(timeout: 5))
        XCTAssertFalse(app.tabBars.firstMatch.isHittable)
        XCTAssertTrue(app.staticTexts["Private · Only you and Pip"].exists)
        let ownMessage = app.staticTexts["Check whether other projects are affected too."]
        let reply = app.staticTexts["The build listing became slower after this morning’s deployment. I’m comparing the query plans."]
        XCTAssertGreaterThan(ownMessage.frame.maxX, reply.frame.maxX)
        capture(app, "ios-orbit-private-preview")
        composer.tap()
        composer.typeText("Can you compare the timings?")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["thread-send"].isHittable)
        capture(app, "ios-orbit-keyboard-preview")
        app.buttons["thread-send"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.tabBars.buttons["Orbit"].waitForExistence(timeout: 5))
        let shared = app.descendants(matching: .any)["thread-01922cc0-0000-7000-8000-000000000002"].firstMatch
        XCTAssertTrue(shared.waitForExistence(timeout: 5))
        shared.tap()
        XCTAssertTrue(app.navigationBars["Build listing latency"].waitForExistence(timeout: 5))
        let tool = try app.visibleElement("Query plans · succeeded")
        tool.tap()
        let resultCard = app.descendants(matching: .any)["thread-result-table"].firstMatch
        XCTAssertTrue(resultCard.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Result"].exists)
        capture(app, "ios-orbit-nsh-card-preview")
        let source = try app.visibleElement("thread-card-source")
        XCTAssertGreaterThanOrEqual(source.frame.height, 44)
        source.tap()
        XCTAssertTrue(app.staticTexts["Result"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.tabBars.firstMatch.isHittable)
        let ask = app.buttons["thread-address-agent"]
        XCTAssertTrue(ask.exists)
        XCTAssertEqual(ask.value as? String, "Off")
        XCTAssertGreaterThanOrEqual(ask.frame.height, 44)
        ask.tap()
        XCTAssertEqual(ask.value as? String, "On")
        capture(app, "ios-orbit-tools-preview")
        app.buttons["thread-info"].tap()
        XCTAssertTrue(app.staticTexts["Comparing query plans across affected projects."].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
    }

    @MainActor func testLegacyServerToolOutputStillRendersWithoutNSH() throws {
        let app = XCUIApplication(bundleIdentifier: "dev.tuist.atlas.settings-preview")
        app.launchArguments = ["--workspace", "--legacy-thread-cards"]
        app.launch()
        defer { app.terminate() }
        let privateThread = app.buttons["orbit-private"]
        XCTAssertTrue(privateThread.waitForExistence(timeout: 10))
        privateThread.tap()
        try app.visibleElement("Query plans · succeeded").tap()
        XCTAssertTrue(app.staticTexts["The new filter bypasses the existing index."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["thread-result-table"].firstMatch.exists)
    }

    @MainActor func testLargeTextDarkThreadKeepsComposerAboveKeyboard() throws {
        let app = XCUIApplication(bundleIdentifier: "dev.tuist.atlas.settings-preview")
        app.launchArguments = ["--workspace", "--dark", "--large-text"]
        app.launch()
        defer { app.terminate() }
        XCUIDevice.shared.orientation = .portrait
        let privateThread = app.buttons["orbit-private"]
        XCTAssertTrue(privateThread.waitForExistence(timeout: 10))
        privateThread.tap()
        let composer = app.textFields["thread-composer"]
        XCTAssertTrue(composer.waitForExistence(timeout: 5))
        XCTAssertFalse(app.tabBars.firstMatch.isHittable)
        XCTAssertTrue(app.staticTexts["Check whether other projects are affected too."].isHittable)
        capture(app, "ios-orbit-large-dark-preview")
        try app.visibleElement("Query plans · succeeded").tap()
        let source = try app.visibleElement("thread-card-source")
        XCTAssertGreaterThanOrEqual(source.frame.height, 44)
        XCTAssertTrue(app.descendants(matching: .any)["thread-result-table"].firstMatch.exists)
        capture(app, "ios-orbit-nsh-large-dark-preview")
        composer.tap()
        composer.typeText("Compare timings")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        let send = app.buttons["thread-send"]
        XCTAssertTrue(send.isHittable)
        XCTAssertLessThanOrEqual(send.frame.maxY, app.keyboards.firstMatch.frame.minY)
        capture(app, "ios-orbit-large-dark-keyboard-preview")
    }

    @MainActor func testAgentActivityChangesWithoutReloadingHistory() throws {
        let app = XCUIApplication(bundleIdentifier: "dev.tuist.atlas.settings-preview")
        app.launchArguments = ["--workspace", "--orbit-activity"]
        app.launch()
        defer { app.terminate() }
        let privateThread = app.buttons["orbit-private"]
        XCTAssertTrue(privateThread.waitForExistence(timeout: 10))
        privateThread.tap()
        XCTAssertTrue(app.staticTexts["Pip is getting ready…"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Pip is responding…"].waitForExistence(timeout: 8))
        let activity = app.staticTexts["thread-agent-activity"]
        let composer = app.textFields["thread-composer"]
        XCTAssertTrue(app.scrollViews.firstMatch.frame.contains(activity.frame))
        XCTAssertLessThanOrEqual(activity.frame.maxY, composer.frame.minY)
        capture(app, "ios-orbit-working-preview")
        XCTAssertTrue(app.staticTexts["Compacting context…"].waitForExistence(timeout: 8))
        capture(app, "ios-orbit-compacting-preview")
        XCTAssertTrue(app.staticTexts["Compacting context…"].waitForNonExistence(timeout: 8))
        XCTAssertTrue(app.textFields["thread-composer"].isHittable)
    }

    @MainActor func testAccountCardAndNativeMarkdown() throws {
        try checkRichThread(largeDark: false)
    }

    @MainActor func testAccountCardAndNativeMarkdownWithLargeDarkText() throws {
        try checkRichThread(largeDark: true)
    }

    @MainActor private func checkRichThread(largeDark: Bool) throws {
        let app = XCUIApplication(bundleIdentifier: "dev.tuist.atlas.settings-preview")
        app.launchArguments = ["--workspace", "--orbit-rich"] + (largeDark ? ["--dark", "--large-text"] : [])
        app.launch()
        defer { app.terminate() }
        XCUIDevice.shared.orientation = .portrait
        app.tabBars.buttons["Profile"].tap()
        try app.visibleElement("profile-appearance").tap()
        try app.visibleElement("theme-habibi").tap()
        app.tabBars.buttons["Orbit"].tap()
        let privateThread = app.buttons["orbit-private"]
        XCTAssertTrue(privateThread.waitForExistence(timeout: 10))
        privateThread.tap()
        let microphone = app.buttons["thread-microphone"]
        XCTAssertTrue(microphone.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(microphone.frame.height, 44)
        let accountCard = try app.visibleElement("thread-account-card", up: false)
        XCTAssertTrue(accountCard.isHittable)
        let source = try visibleCardSource(in: app)
        XCTAssertGreaterThanOrEqual(source.frame.height, 44)
        XCTAssertFalse(app.staticTexts["Result"].exists)
        capture(app, "ios-orbit-account-card-habibi-\(largeDark ? "large-dark" : "light")-preview")
        source.tap()
        XCTAssertTrue(try app.visibleElement("Result").isHittable)
        for _ in 0..<8 where !app.staticTexts["Account overview"].isHittable { app.scrollContent(up: false) }
        XCTAssertTrue(app.staticTexts["Account overview"].isHittable)
        capture(app, "ios-orbit-markdown-\(largeDark ? "large-dark" : "light")-preview")
    }

    @MainActor private func visibleCardSource(in app: XCUIApplication) throws -> XCUIElement {
        let source = app.descendants(matching: .any).matching(identifier: "thread-card-source").firstMatch
        let composer = app.textFields["thread-composer"]
        for _ in 0..<10 {
            // NativeShell can expose an offscreen child as hittable. Require its whole target inside the transcript.
            let top = app.navigationBars.firstMatch.frame.maxY
            let bottom = composer.frame.minY
            if source.exists, source.isHittable, source.frame.minY >= top, source.frame.maxY <= bottom { return source }
            app.scrollContent(up: !source.exists || source.frame.maxY > bottom)
        }
        return try XCTUnwrap(nil as XCUIElement?, "Missing visible account-card source action")
    }

    @MainActor func testInlineAccountEvidenceHeaderRevealsSource() throws {
        let app = XCUIApplication(bundleIdentifier: "dev.tuist.atlas.settings-preview")
        app.launchArguments = ["--workspace", "--orbit-rich"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["orbit-private"].waitForExistence(timeout: 10))
        app.buttons["orbit-private"].tap()
        XCTAssertTrue(app.textFields["thread-composer"].waitForExistence(timeout: 5))
        try app.visibleElement("Account lookup · succeeded").tap()
        XCTAssertTrue(try app.visibleElement("Result").isHittable)
        capture(app, "ios-orbit-inline-account-expanded-evidence-preview")
    }

    @MainActor func testComposerActionsAreCompactAndAlignedWithSingleAndMultilineDrafts() throws {
        for arguments in [[], ["--dark", "--large-text"]] {
            let app = XCUIApplication(bundleIdentifier: "dev.tuist.atlas.settings-preview")
            app.launchArguments = ["--workspace"] + arguments
            app.launch()
            defer { app.terminate() }
            XCTAssertTrue(app.buttons["orbit-private"].waitForExistence(timeout: 10))
            app.buttons["orbit-private"].tap()
            let draft = app.textFields["thread-composer"]
            XCTAssertTrue(draft.waitForExistence(timeout: 5))
            for text in ["", "Compare these accounts.", "\nAnd their recent activity.\nInclude the latest billing details."] {
                if !text.isEmpty { draft.tap(); draft.typeText(text) }
                let microphone = app.buttons["thread-microphone"]
                let send = app.buttons["thread-send"]
                XCTAssertEqual(microphone.frame.height, 44, accuracy: 1)
                XCTAssertEqual(send.frame.height, 44, accuracy: 1)
                XCTAssertEqual(send.frame.width, 44, accuracy: 1)
                XCTAssertEqual(send.frame.midY, microphone.frame.midY, accuracy: 1)
                if app.keyboards.firstMatch.exists { XCTAssertLessThanOrEqual(send.frame.maxY, app.keyboards.firstMatch.frame.minY) }
            }
            capture(app, "ios-orbit-composer-aligned-preview")
        }
    }

    @MainActor func testVoiceHoldReleasesToReviewWithoutAcceptingOrSending() throws {
        let app = XCUIApplication(bundleIdentifier: "dev.tuist.atlas.settings-preview")
        app.launchArguments = ["--voice-input"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["thread-voice-cancel"].waitForExistence(timeout: 10))
        app.buttons["thread-voice-cancel"].tap()
        let microphone = app.buttons["thread-microphone"]
        microphone.press(forDuration: 1)
        XCTAssertTrue(app.staticTexts["Review your transcript"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["voice-preview-draft"].value as? String, "Existing draft.")
        capture(app, "ios-orbit-voice-hold-release-fixture")
        app.buttons["thread-voice-cancel"].tap()
        microphone.tap()
        XCTAssertTrue(app.staticTexts["Transcribing on this device"].waitForExistence(timeout: 5))
        microphone.tap()
        XCTAssertTrue(app.staticTexts["Review your transcript"].waitForExistence(timeout: 5))
        app.buttons["thread-voice-done"].tap()
        XCTAssertEqual(app.textFields["voice-preview-draft"].value as? String, "Existing draft. Compare the latest build timings.")
    }

    @MainActor func testVoicePresentationPreservesDraftOnCancelAndAppendsOnlyOnDone() throws {
        for dark in [false, true] {
            let app = XCUIApplication(bundleIdentifier: "dev.tuist.atlas.settings-preview")
            app.launchArguments = ["--voice-input"] + (dark ? ["--dark", "--large-text"] : [])
            app.launch()
            defer { app.terminate() }
            XCUIDevice.shared.orientation = .portrait
            let cancel = app.buttons["thread-voice-cancel"]
            let done = app.buttons["thread-voice-done"]
            XCTAssertTrue(cancel.waitForExistence(timeout: 10))
            XCTAssertGreaterThanOrEqual(cancel.frame.height, 44)
            XCTAssertGreaterThanOrEqual(done.frame.height, 44)
            XCTAssertTrue(done.isHittable)
            capture(app, "ios-orbit-voice-\(dark ? "large-dark" : "light")-fixture")
            cancel.tap()
            let draft = app.textFields["voice-preview-draft"]
            XCTAssertTrue(draft.waitForExistence(timeout: 5))
            XCTAssertEqual(draft.value as? String, "Existing draft.")
            app.buttons["Transcribe fixture"].tap()
            done.tap()
            XCTAssertTrue(draft.waitForExistence(timeout: 5))
            XCTAssertEqual(draft.value as? String, "Existing draft. Compare the latest build timings.")
        }
    }

    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
