import XCTest

@MainActor
final class AtlasBusinessUITests: XCTestCase {
    func testTaskCreateEditCompleteAndDelete() throws {
        let app = launch()
        defer { app.terminate() }

        app.buttons["business-create"].tap()
        let title = app.textFields["business-field-title"]
        title.tap()
        title.typeText("Plan customer workshop")
        app.buttons["business-save"].tap()
        try visible("Plan customer workshop", in: app).tap()
        XCTAssertTrue(app.navigationBars["Task"].waitForExistence(timeout: 5))
        app.buttons["Edit"].tap()
        XCTAssertEqual(title.value as? String, "Plan customer workshop")
        app.buttons["Cancel"].tap()
        try visible("Mark complete", in: app).tap()
        XCTAssertTrue(app.staticTexts["completed"].waitForExistence(timeout: 5))
        try visible("Delete task", in: app).tap()
        app.buttons["Delete"].tap()
        XCTAssertTrue(app.navigationBars["Tasks"].waitForExistence(timeout: 5))
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "dev.tuist.atlas.settings-preview")
        app.launchArguments = ["--workspace"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Browse"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Browse"].tap()
        let tasks = app.descendants(matching: .any)["workspace-section-tasks"].firstMatch
        XCTAssertTrue(tasks.waitForExistence(timeout: 5))
        tasks.tap()
        XCTAssertTrue(app.buttons["business-create"].waitForExistence(timeout: 10))
        return app
    }

    private func visible(_ id: String, in app: XCUIApplication) throws -> XCUIElement {
        try app.visibleElement(id)
    }
}
