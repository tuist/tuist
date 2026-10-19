import XCTest

final class AtlasWorkspaceUITests: XCTestCase {
    @MainActor func testDomainDrillDownAndBrowserFallbackOnSelectedServer() throws {
        let app = launch()
        defer { app.terminate() }
        XCTAssertTrue(app.navigationBars["Atlas"].waitForExistence(timeout: 10))
        attach(app, "ios-workspace-home")
        try tap("workspace-group-commercial", in: app)
        XCTAssertTrue(app.navigationBars["Commercial"].exists)
        try tap("workspace-group-sales", in: app)
        XCTAssertTrue(app.navigationBars["Sales"].exists)
        attach(app, "ios-workspace-sales")
        try tap("workspace-section-accounts", in: app)
        XCTAssertTrue(app.alerts["Link preview"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.alerts.staticTexts["https://atlas.example.org/commercial/sales/accounts"].exists)
        app.alerts.buttons["Done"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Commercial"].exists)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Atlas"].exists)
        try tap("workspace-group-people", in: app)
        try tap("workspace-section-time-off", in: app)
        XCTAssertTrue(app.navigationBars["Time off"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["People"].exists)
        try tap("workspace-settings", in: app)
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["People"].exists)
    }

    @MainActor func testGlobalFeatureSearchInDarkAccessibilityText() throws {
        let app = launch(arguments: ["--dark", "--large-text"])
        defer { app.terminate() }
        XCTAssertTrue(app.navigationBars["Atlas"].waitForExistence(timeout: 10))
        let search = app.searchFields.firstMatch
        if !search.isHittable { app.swipeDown() }
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("vendor")
        let result = try visible("workspace-section-vendors", in: app)
        XCTAssertGreaterThanOrEqual(result.frame.height, 44)
        attach(app, "ios-workspace-search-large-dark")
        result.tap()
        XCTAssertTrue(app.alerts["Link preview"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.alerts.staticTexts["https://atlas.example.org/commercial/finance/vendors"].exists)
    }

    @MainActor private func launch(arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--workspace"] + arguments
        app.launch()
        return app
    }

    @MainActor private func visible(_ id: String, in app: XCUIApplication) throws -> XCUIElement {
        for _ in 0..<7 {
            if let element = app.descendants(matching: .any).matching(identifier: id).allElementsBoundByIndex.first(where: \.isHittable) {
                return element
            }
            app.swipeUp()
        }
        return try XCTUnwrap(nil as XCUIElement?, "Missing workspace destination: \(id)")
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
