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
        XCTAssertTrue(app.textFields["conversation-composer"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Private · Only you and Juniper"].exists)
        capture(app, "ios-conversations-private-preview")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let shared = app.descendants(matching: .any)["conversation-01922cc0-0000-7000-8000-000000000002"].firstMatch
        XCTAssertTrue(shared.waitForExistence(timeout: 5))
        shared.tap()
        XCTAssertTrue(app.navigationBars["Build listing latency"].waitForExistence(timeout: 5))
        let tool = try app.visibleElement("Query plans · completed")
        tool.tap()
        XCTAssertTrue(app.staticTexts["The new filter bypasses the existing index."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.switches["Ask Juniper"].exists)
        capture(app, "ios-conversations-tools-preview")
    }

    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
