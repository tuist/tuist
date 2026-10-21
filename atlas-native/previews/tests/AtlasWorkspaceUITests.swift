import XCTest

final class AtlasWorkspaceUITests: XCTestCase {
    @MainActor func testStableTabsNativeBrowseAndProfile() throws {
        let app = launch()
        defer { app.terminate() }
        XCTAssertTrue(app.navigationBars["Tasks"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.tabBars.buttons.count, 5)
        XCTAssertFalse(app.tabBars.buttons["More"].exists)
        attach(app, "ios-workspace-tasks")
        app.tabBars.buttons["Accounts"].tap()
        XCTAssertTrue(app.staticTexts["Northstar"].waitForExistence(timeout: 5))
        attach(app, "ios-workspace-accounts")
        app.tabBars.buttons["Finance"].tap()
        let chartHeading = app.staticTexts.matching(NSPredicate(format: "label ==[c] %@", "Monthly invoice totals")).firstMatch
        XCTAssertTrue(chartHeading.waitForExistence(timeout: 5))
        attach(app, "ios-workspace-finance")
        app.tabBars.buttons["Browse"].tap()
        XCTAssertTrue(app.navigationBars["Browse"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["workspace-group-engineering"].exists)
        attach(app, "ios-workspace-browse")
        try tap("workspace-group-commercial", in: app)
        try tap("workspace-group-sales", in: app)
        try tap("workspace-section-accounts", in: app)
        XCTAssertTrue(app.navigationBars["Accounts"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.alerts["Link preview"].exists)
        app.tabBars.buttons["Profile"].tap()
        XCTAssertTrue(app.staticTexts["Taylor Morgan"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "0.7.2")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts["https://atlas.example.org"].exists)
        attach(app, "ios-workspace-profile")
        try tap("ai-account-claude", in: app)
        XCTAssertTrue(app.secureTextFields["claude-token"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        try tap("ai-account-chatgpt", in: app)
        XCTAssertTrue(app.buttons["Sign in with ChatGPT"].waitForExistence(timeout: 5))
    }

    @MainActor func testNativeSearchInDarkAccessibilityText() throws {
        let app = launch(arguments: ["--dark", "--large-text"])
        defer { app.terminate() }
        XCTAssertTrue(app.navigationBars["Tasks"].waitForExistence(timeout: 10))
        attach(app, "ios-workspace-tasks-large-dark")
        app.tabBars.buttons["Browse"].tap()
        let search = app.searchFields.firstMatch
        if !search.isHittable {
            if app.buttons["Search"].exists { app.buttons["Search"].tap() } else { app.scrollContent(up: false) }
        }
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("vendor")
        XCTAssertFalse(app.descendants(matching: .any)["workspace-section-vendors"].exists)
        search.tap()
        search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 6) + "holiday")
        try tap("workspace-section-time-off", in: app)
        XCTAssertTrue(app.navigationBars["Time off"].waitForExistence(timeout: 5))
        attach(app, "ios-workspace-time-off-large-dark")
    }

    @MainActor private func launch(arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "dev.tuist.atlas.settings-preview")
        app.launchArguments = ["--workspace"] + arguments
        app.launch()
        XCUIDevice.shared.orientation = .portrait
        return app
    }

    @MainActor private func visible(_ id: String, in app: XCUIApplication) throws -> XCUIElement {
        try app.visibleElement(id)
    }

    @MainActor private func tap(_ id: String, in app: XCUIApplication) throws {
        let element = try visible(id, in: app)
        XCTAssertGreaterThanOrEqual(element.frame.height, 44)
        element.tap()
    }

    @MainActor private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
