import XCTest

final class AtlasOrbitUITests: XCTestCase {
    @MainActor func testPrivateThreadAndSharedToolEvidence() throws {
        let app = XCUIApplication(bundleIdentifier: "dev.tuist.atlas.settings-preview")
        app.launchArguments = ["--workspace"]
        app.launch()
        defer { app.terminate() }
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(app.navigationBars["Orbit"].waitForExistence(timeout: 10))
        let privateThread = app.buttons["thread-01922cc0-0000-7000-8000-000000000001"]
        XCTAssertTrue(privateThread.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(privateThread.frame.height, 44)
        XCTAssertFalse(app.buttons["thread-01922cc0-0000-7000-8000-000000000002"].exists)
        XCTAssertFalse(app.buttons["Ask Pip"].exists)
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
        app.terminate()
        app.launchArguments = ["--workspace", "--destination",
            "dev.tuist.atlas://navigate/orbit/01922cc0-0000-7000-8000-000000000002?server=https%3A%2F%2Fatlas.example.org"]
        app.launch()
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
        let privateThread = app.buttons["thread-01922cc0-0000-7000-8000-000000000001"]
        XCTAssertTrue(privateThread.waitForExistence(timeout: 10))
        privateThread.tap()
        try app.visibleElement("Query plans · succeeded").tap()
        XCTAssertTrue(app.staticTexts["The new filter bypasses the existing index."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["thread-result-table"].firstMatch.exists)
    }

    @MainActor func testAttachmentChipCenterOpensDownloadedFile() throws {
        let app = XCUIApplication(bundleIdentifier: "dev.tuist.atlas.settings-preview")
        app.launchArguments = ["--workspace", "--orbit-attachments", "--destination",
            "dev.tuist.atlas://navigate/orbit/01922cc0-0000-7000-8000-000000000001?server=https%3A%2F%2Fatlas.example.org"]
        app.launch()
        defer { app.terminate() }
        XCUIDevice.shared.orientation = .portrait
        let remove = app.buttons["Remove notes.txt"]
        XCTAssertTrue(remove.waitForExistence(timeout: 10))
        remove.tap()
        XCTAssertTrue(remove.waitForNonExistence(timeout: 5))
        let file = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "notes.txt")).firstMatch
        file.tap()
        XCTAssertTrue(app.buttons["QLOverlayDoneButtonAccessibilityIdentifier"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textViews["Atlas attachment fixture. No private data."].waitForExistence(timeout: 10))
        capture(app, "ios-orbit-attachment-preview")
    }

    @MainActor func testLargeTextDarkThreadKeepsComposerAboveKeyboard() throws {
        let app = XCUIApplication(bundleIdentifier: "dev.tuist.atlas.settings-preview")
        app.launchArguments = ["--workspace", "--dark", "--large-text"]
        app.launch()
        defer { app.terminate() }
        XCUIDevice.shared.orientation = .portrait
        let privateThread = app.buttons["thread-01922cc0-0000-7000-8000-000000000001"]
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
        let privateThread = app.buttons["thread-01922cc0-0000-7000-8000-000000000001"]
        XCTAssertTrue(privateThread.waitForExistence(timeout: 10))
        privateThread.tap()
        XCTAssertTrue(app.staticTexts["Pip is getting ready…"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Typing…"].waitForExistence(timeout: 8))
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
        let privateThread = app.buttons["thread-01922cc0-0000-7000-8000-000000000001"]
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
        XCTAssertTrue(app.buttons["thread-01922cc0-0000-7000-8000-000000000001"].waitForExistence(timeout: 10))
        app.buttons["thread-01922cc0-0000-7000-8000-000000000001"].tap()
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
            XCTAssertTrue(app.buttons["thread-01922cc0-0000-7000-8000-000000000001"].waitForExistence(timeout: 10))
            app.buttons["thread-01922cc0-0000-7000-8000-000000000001"].tap()
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

    @MainActor func testVoiceHoldReleasesIntoEditableDraftWithoutSending() throws {
        let app = XCUIApplication(bundleIdentifier: "dev.tuist.atlas.settings-preview")
        app.launchArguments = ["--voice-input"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["thread-voice-cancel"].waitForExistence(timeout: 10))
        app.buttons["thread-voice-cancel"].tap()
        let microphone = app.buttons["thread-microphone"]
        microphone.press(forDuration: 1)
        let draft = app.textFields["thread-composer"]
        XCTAssertTrue(draft.waitForExistence(timeout: 5))
        XCTAssertEqual(draft.value as? String, "Existing draft. Compare the latest build timings.")
        XCTAssertFalse(app.descendants(matching: .any)["thread-voice-recording"].exists)
        XCTAssertFalse(app.buttons["thread-voice-done"].exists)
        capture(app, "ios-orbit-voice-hold-release-fixture")
        draft.tap()
        draft.typeText(" Ready to edit.")
        let edited = try XCTUnwrap(draft.value as? String)
        XCTAssertTrue(edited.contains("Ready to edit."))
        XCTAssertTrue(edited.contains("Compare the latest build timings."))
        microphone.tap()
        XCTAssertTrue(app.descendants(matching: .any)["thread-voice-recording"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Compare the latest build timings."].exists)
        microphone.tap()
        XCTAssertTrue(draft.waitForExistence(timeout: 5))
        XCTAssertEqual(draft.value as? String, edited + " Compare the latest build timings.")
    }

    @MainActor func testVoicePresentationDiscardsOnCancelAndAppendsOnStop() throws {
        for dark in [false, true] {
            let app = XCUIApplication(bundleIdentifier: "dev.tuist.atlas.settings-preview")
            app.launchArguments = ["--voice-input"] + (dark ? ["--dark", "--large-text"] : [])
            app.launch()
            defer { app.terminate() }
            XCUIDevice.shared.orientation = .portrait
            let cancel = app.buttons["thread-voice-cancel"]
            let stop = app.buttons["thread-microphone"]
            XCTAssertTrue(cancel.waitForExistence(timeout: 10))
            XCTAssertGreaterThanOrEqual(cancel.frame.height, 44)
            XCTAssertGreaterThanOrEqual(stop.frame.height, 44)
            XCTAssertTrue(stop.isHittable)
            XCTAssertFalse(app.buttons["thread-send"].exists)
            XCTAssertFalse(app.staticTexts["Compare the latest build timings."].exists)
            capture(app, "ios-orbit-voice-\(dark ? "large-dark" : "light")-fixture")
            cancel.tap()
            let draft = app.textFields["thread-composer"]
            XCTAssertTrue(draft.waitForExistence(timeout: 5))
            XCTAssertEqual(draft.value as? String, "Existing draft.")
            app.buttons["Transcribe fixture"].tap()
            stop.tap()
            XCTAssertTrue(draft.waitForExistence(timeout: 5))
            XCTAssertEqual(draft.value as? String, "Existing draft. Compare the latest build timings.")
            capture(app, "ios-orbit-voice-editable-\(dark ? "large-dark" : "light")-fixture")
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
            capture(app, "ios-orbit-prompt-index-\(dark ? "shared-dark-large" : "private-light")")
            app.buttons["Load earlier prompts"].tap()
            let first = app.buttons["thread-prompt-prompt-0"]
            XCTAssertTrue(first.waitForExistence(timeout: 5))
            XCTAssertTrue(first.label.contains("release-notes.txt"))
            XCTAssertFalse(app.buttons["Load earlier prompts"].exists)
            first.tap()
            XCTAssertTrue(app.navigationBars["Prompts"].waitForNonExistence(timeout: 5))
            let attachment = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "release-notes.txt")).firstMatch
            XCTAssertTrue(attachment.waitForExistence(timeout: 5))
            XCTAssertTrue(attachment.isHittable)
            XCTAssertGreaterThanOrEqual(attachment.frame.minY, app.navigationBars.firstMatch.frame.maxY)
            XCTAssertEqual(composer.value as? String, "Keep this draft.")
            capture(app, "ios-orbit-prompt-jump-\(dark ? "shared-dark-large" : "private-light")")
            app.buttons["Latest messages"].tap()
            XCTAssertTrue(app.staticTexts["Summarize the next steps."].isHittable)
            XCTAssertFalse(attachment.isHittable)
            XCTAssertEqual(composer.value as? String, "Keep this draft.")
            app.terminate()
        }
    }

    @MainActor func testComposeCreatesSeparatePrivateConversationsWithSuggestions() throws {
        for arguments in [[], ["--dark", "--large-text"]] {
            let app = XCUIApplication(bundleIdentifier: "dev.tuist.atlas.settings-preview")
            app.launchArguments = ["--workspace"] + arguments
            app.launch()
            defer { app.terminate() }
            XCUIDevice.shared.orientation = .portrait
            let compose = app.buttons["orbit-create"]
            XCTAssertTrue(compose.waitForExistence(timeout: 10))
            XCTAssertFalse(app.buttons["pip-mascot"].exists)
            XCTAssertFalse(app.buttons["thread-01922cc0-0000-7000-8000-000000000002"].exists)
            capture(app, "ios-orbit-conversations-\(arguments.isEmpty ? "light" : "dark-large")-preview")
            compose.tap()
            let mascot = app.buttons["pip-mascot"]
            XCTAssertTrue(mascot.waitForExistence(timeout: 5))
            capture(app, "ios-orbit-new-conversation-\(arguments.isEmpty ? "light" : "dark-large")-preview")
            mascot.tap()
            mascot.press(forDuration: 0.8)
            let draft = app.textFields["thread-composer"]
            draft.tap()
            draft.typeText("Prepare an October release.")
            app.buttons["thread-send"].tap()
            XCTAssertTrue(app.staticTexts["Prepare an October release."].waitForExistence(timeout: 5))
            app.navigationBars.buttons.element(boundBy: 0).tap()
            XCTAssertTrue(compose.waitForExistence(timeout: 5))
            compose.tap()
            XCTAssertTrue(mascot.waitForExistence(timeout: 5))
            XCTAssertEqual(draft.value as? String, "Ask Pip")
            XCTAssertFalse(app.staticTexts["Prepare an October release."].exists)
            app.terminate()
        }
    }

    @MainActor func testBottomFollowsAppendedAndGrowingReplyWithoutMovingHistoryReaders() throws {
        for readingHistory in [false, true] {
            let app = XCUIApplication(bundleIdentifier: "dev.tuist.atlas.settings-preview")
            app.launchArguments = ["--workspace", "--orbit-follow"] + (readingHistory ? ["--orbit-prompts"] : [])
            app.launch()
            defer { app.terminate() }
            XCUIDevice.shared.orientation = .portrait
            let conversation = app.buttons["thread-01922cc0-0000-7000-8000-000000000001"]
            XCTAssertTrue(conversation.waitForExistence(timeout: 10))
            conversation.tap()
            XCTAssertTrue(app.textFields["thread-composer"].waitForExistence(timeout: 5))
            if readingHistory {
                app.buttons["thread-prompts"].tap()
                app.buttons["Load earlier prompts"].tap()
                let first = app.buttons["thread-prompt-prompt-0"]
                XCTAssertTrue(first.waitForExistence(timeout: 5))
                first.tap()
                XCTAssertTrue(app.navigationBars["Prompts"].waitForNonExistence(timeout: 5))
            } else {
                let appended = app.staticTexts["A new reply appeared."]
                XCTAssertTrue(appended.waitForExistence(timeout: 10))
                XCTAssertTrue(appended.isHittable)
            }
            let complete = app.staticTexts["The growing reply is complete."]
            if readingHistory {
                // An offscreen lazy row need not exist in accessibility while its body grows.
                let started = Date()
                let delivered = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                    Date().timeIntervalSince(started) >= 13
                }, object: nil)
                XCTAssertEqual(XCTWaiter.wait(for: [delivered], timeout: 15), .completed)
                let firstPrompt = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "release-notes.txt")).firstMatch
                XCTAssertTrue(firstPrompt.isHittable)
                XCTAssertFalse(complete.isHittable)
                XCTAssertTrue(app.buttons["Latest messages"].isHittable)
                capture(app, "ios-orbit-growing-reply-history-retained-preview")
                app.buttons["Latest messages"].tap()
                XCTAssertTrue(complete.waitForExistence(timeout: 5))
            } else {
                XCTAssertTrue(complete.waitForExistence(timeout: 15))
                let follows = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                    complete.isHittable && complete.frame.maxY <= app.textFields["thread-composer"].frame.minY
                }, object: nil)
                XCTAssertEqual(XCTWaiter.wait(for: [follows], timeout: 5), .completed)
                capture(app, "ios-orbit-growing-reply-follow-latest-preview")
            }
            app.terminate()
        }
    }

    @MainActor func testSlowConversationEntryShowsLoadingThenPagesAutomaticallyUpward() throws {
        let app = XCUIApplication(bundleIdentifier: "dev.tuist.atlas.settings-preview")
        app.launchArguments = ["--workspace", "--orbit-prompts", "--delayed-orbit"]
        app.launch()
        defer { app.terminate() }
        let conversation = app.buttons["thread-01922cc0-0000-7000-8000-000000000001"]
        XCTAssertTrue(conversation.waitForExistence(timeout: 10))
        conversation.tap()
        let loading = app.descendants(matching: .any)["thread-history-loading"].firstMatch
        XCTAssertTrue(loading.waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["Compare recent builds"].exists)
        capture(app, "ios-orbit-history-loading-preview")
        XCTAssertTrue(loading.waitForNonExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Summarize the next steps."].isHittable)
        for _ in 0..<8 { app.scrollContent(up: false) }
        app.buttons["thread-prompts"].tap()
        XCTAssertTrue(app.buttons["thread-prompt-prompt-0"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Load earlier prompts"].exists)
        capture(app, "ios-orbit-automatically-paged-prompts-preview")
    }

    @MainActor func testScrollingDuringEarlierPageLoadKeepsTheCurrentVisibleMessage() throws {
        let app = XCUIApplication(bundleIdentifier: "dev.tuist.atlas.settings-preview")
        app.launchArguments = ["--workspace", "--orbit-prompts", "--delayed-orbit-history"]
        app.launch()
        defer { app.terminate() }
        XCUIDevice.shared.orientation = .portrait
        let conversation = app.buttons["thread-01922cc0-0000-7000-8000-000000000001"]
        XCTAssertTrue(conversation.waitForExistence(timeout: 10))
        conversation.tap()
        XCTAssertTrue(app.textFields["thread-composer"].waitForExistence(timeout: 5))
        let loading = app.buttons["Loading earlier messages…"]
        for _ in 0..<8 {
            if loading.exists { break }
            app.scrollContent(up: false)
        }
        XCTAssertTrue(loading.waitForExistence(timeout: 3))
        app.scrollContent()
        let candidates = ["Check the build listing query plan.", "Does it affect other projects?", "Review the proposed index.",
                          "What are the rollout risks?", "Include a concise validation checklist."]
        let visible = try XCTUnwrap(candidates.map { app.staticTexts[$0] }.first {
            $0.isHittable && $0.frame.minY > app.navigationBars.firstMatch.frame.maxY
                && $0.frame.maxY < app.textFields["thread-composer"].frame.minY
        })
        let before = visible.frame
        XCTAssertTrue(loading.waitForNonExistence(timeout: 12))
        XCTAssertTrue(visible.isHittable)
        XCTAssertEqual(visible.frame.minY, before.minY, accuracy: 3)
        capture(app, "ios-orbit-earlier-page-retains-reader-preview")
    }

    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
