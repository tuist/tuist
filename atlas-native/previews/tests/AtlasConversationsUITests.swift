import XCTest

final class AtlasConversationsUITests: XCTestCase {
    @MainActor func testPrivateThreadAndSharedToolEvidence() throws {
        let app = XCUIApplication(bundleIdentifier: "dev.tuist.atlas.settings-preview")
        app.launchArguments = ["--workspace"]
        app.launch()
        defer { app.terminate() }
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(app.navigationBars["Conversations"].waitForExistence(timeout: 10))
        let privateThread = app.buttons["conversations-private"]
        XCTAssertTrue(privateThread.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(privateThread.frame.height, 44)
        capture(app, "ios-conversations-list-preview")
        privateThread.tap()
        XCTAssertTrue(app.navigationBars["Juniper"].waitForExistence(timeout: 5))
        let composer = app.textFields["conversation-composer"]
        XCTAssertTrue(composer.waitForExistence(timeout: 5))
        XCTAssertFalse(app.tabBars.firstMatch.isHittable)
        XCTAssertTrue(app.staticTexts["Private · Only you and Juniper"].exists)
        let ownMessage = app.staticTexts["Check whether other projects are affected too."]
        let reply = app.staticTexts["The build listing became slower after this morning’s deployment. I’m comparing the query plans."]
        XCTAssertGreaterThan(ownMessage.frame.maxX, reply.frame.maxX)
        capture(app, "ios-conversations-private-preview")
        composer.tap()
        composer.typeText("Can you compare the timings?")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["conversation-send"].isHittable)
        capture(app, "ios-conversations-keyboard-preview")
        app.buttons["conversation-send"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.tabBars.buttons["Conversations"].waitForExistence(timeout: 5))
        let shared = app.descendants(matching: .any)["conversation-01922cc0-0000-7000-8000-000000000002"].firstMatch
        XCTAssertTrue(shared.waitForExistence(timeout: 5))
        shared.tap()
        XCTAssertTrue(app.navigationBars["Build listing latency"].waitForExistence(timeout: 5))
        let tool = try app.visibleElement("Query plans · succeeded")
        tool.tap()
        let resultCard = app.descendants(matching: .any)["conversation-result-table"].firstMatch
        XCTAssertTrue(resultCard.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Result"].exists)
        capture(app, "ios-conversations-nsh-card-preview")
        let source = try app.visibleElement("conversation-card-source")
        XCTAssertGreaterThanOrEqual(source.frame.height, 44)
        source.tap()
        XCTAssertTrue(app.staticTexts["Result"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.tabBars.firstMatch.isHittable)
        let ask = app.buttons["conversation-address-agent"]
        XCTAssertTrue(ask.exists)
        XCTAssertEqual(ask.value as? String, "Off")
        XCTAssertGreaterThanOrEqual(ask.frame.height, 44)
        ask.tap()
        XCTAssertEqual(ask.value as? String, "On")
        capture(app, "ios-conversations-tools-preview")
        app.buttons["conversation-info"].tap()
        XCTAssertTrue(app.staticTexts["Comparing query plans across affected projects."].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
    }

    @MainActor func testLegacyServerToolOutputStillRendersWithoutNSH() throws {
        let app = XCUIApplication(bundleIdentifier: "dev.tuist.atlas.settings-preview")
        app.launchArguments = ["--workspace", "--legacy-conversation-cards"]
        app.launch()
        defer { app.terminate() }
        let privateThread = app.buttons["conversations-private"]
        XCTAssertTrue(privateThread.waitForExistence(timeout: 10))
        privateThread.tap()
        try app.visibleElement("Query plans · succeeded").tap()
        XCTAssertTrue(app.staticTexts["The new filter bypasses the existing index."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["conversation-result-table"].firstMatch.exists)
    }

    @MainActor func testLargeTextDarkConversationKeepsComposerAboveKeyboard() throws {
        let app = XCUIApplication(bundleIdentifier: "dev.tuist.atlas.settings-preview")
        app.launchArguments = ["--workspace", "--dark", "--large-text"]
        app.launch()
        defer { app.terminate() }
        XCUIDevice.shared.orientation = .portrait
        let privateThread = app.buttons["conversations-private"]
        XCTAssertTrue(privateThread.waitForExistence(timeout: 10))
        privateThread.tap()
        let composer = app.textFields["conversation-composer"]
        XCTAssertTrue(composer.waitForExistence(timeout: 5))
        XCTAssertFalse(app.tabBars.firstMatch.isHittable)
        XCTAssertTrue(app.staticTexts["Check whether other projects are affected too."].isHittable)
        capture(app, "ios-conversations-large-dark-preview")
        try app.visibleElement("Query plans · succeeded").tap()
        let source = try app.visibleElement("conversation-card-source")
        XCTAssertGreaterThanOrEqual(source.frame.height, 44)
        XCTAssertTrue(app.descendants(matching: .any)["conversation-result-table"].firstMatch.exists)
        capture(app, "ios-conversations-nsh-large-dark-preview")
        composer.tap()
        composer.typeText("Compare timings")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        let send = app.buttons["conversation-send"]
        XCTAssertTrue(send.isHittable)
        XCTAssertLessThanOrEqual(send.frame.maxY, app.keyboards.firstMatch.frame.minY)
        capture(app, "ios-conversations-large-dark-keyboard-preview")
    }

    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
