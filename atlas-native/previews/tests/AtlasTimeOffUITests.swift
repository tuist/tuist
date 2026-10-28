import XCTest

final class AtlasTimeOffUITests: XCTestCase {
    @MainActor func testEmployeeHolidayScreensAndEditing() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--time-off"]
        app.launch()
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(app.navigationBars["Time off"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["Edit request"].firstMatch.exists)
        XCTAssertGreaterThanOrEqual(app.buttons["Edit request"].firstMatch.frame.height, 44)
        XCTAssertGreaterThanOrEqual(app.buttons["Cancel holiday"].firstMatch.frame.height, 44)
        attach(app, "ios-time-off-overview")
        app.buttons["Edit request"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Edit request"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "holiday-start-date").firstMatch.exists)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "holiday-end-date").firstMatch.exists)
        attach(app, "ios-time-off-edit")
        app.buttons["Save changes"].tap()
        XCTAssertTrue(app.navigationBars["Time off"].waitForExistence(timeout: 5))
        try tapVisible("Request holiday", in: app)
        XCTAssertTrue(app.navigationBars["Request holiday"].waitForExistence(timeout: 5))
        attach(app, "ios-time-off-request")
        try tapVisible("Request holiday", in: app)
        XCTAssertTrue(app.navigationBars["Time off"].waitForExistence(timeout: 5))
    }

    @MainActor func testFailedSavePreservesEditorInDarkLargeText() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--time-off", "--fail-holiday-save", "--dark", "--large-text"]
        app.launch()
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(app.navigationBars["Time off"].waitForExistence(timeout: 15))
        try tapVisible("Request holiday", in: app)
        XCTAssertTrue(app.navigationBars["Request holiday"].waitForExistence(timeout: 5))
        app.scrollContent()
        try tapVisible("Request holiday", in: app)
        let messages = app.staticTexts.matching(identifier: "Preview save failed. Your dates are still here.")
        XCTAssertTrue(messages.firstMatch.waitForExistence(timeout: 5))
        let message = try app.visibleElement("Preview save failed. Your dates are still here.")
        XCTAssertGreaterThan(message.frame.height, 60)
        attach(app, "ios-time-off-failed-save-large-dark")
    }

    @MainActor private func tapVisible(_ label: String, in app: XCUIApplication) throws {
        let button = try app.visibleElement(label, type: .button)
        XCTAssertGreaterThanOrEqual(button.frame.height, 44)
        button.tap()
    }

    @MainActor private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
