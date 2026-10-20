import XCTest

@MainActor
final class AtlasBusinessUITests: XCTestCase {
    func testTaskCreateEditCompleteAndDelete() throws {
        let app = launch()
        defer { app.terminate() }
        app.buttons["business-create"].tap()
        XCTAssertFalse(app.buttons["business-save"].isEnabled)
        app.textFields["business-field-title"].tap()
        app.textFields["business-field-title"].typeText("Plan customer workshop")
        capture(app, "ios-task-create")
        app.buttons["business-save"].tap()
        try tap("Plan customer workshop", in: app)
        XCTAssertTrue(app.navigationBars["Task"].waitForExistence(timeout: 5))
        app.buttons["Edit"].tap()
        let title = app.textFields["business-field-title"]
        XCTAssertEqual(title.value as? String, "Plan customer workshop")
        title.tap()
        title.typeText(" tomorrow")
        app.buttons["business-save"].tap()
        try tap("Mark complete", in: app)
        XCTAssertTrue(app.staticTexts["completed"].waitForExistence(timeout: 5))
        capture(app, "ios-task-completed")
        try tap("Delete task", in: app)
        app.buttons["Delete"].tap()
        XCTAssertTrue(app.navigationBars["Tasks"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Plan customer workshop tomorrow"].exists)
    }

    func testAccountAndManualInvoiceFormsAndImportedReadOnly() throws {
        let app = launch()
        defer { app.terminate() }
        app.tabBars.buttons["Accounts"].tap()
        app.buttons["business-create"].tap()
        app.textFields["business-field-name"].tap()
        app.textFields["business-field-name"].typeText("Cedar Labs")
        app.buttons["business-save"].tap()
        try tap("Cedar Labs", in: app)
        capture(app, "ios-account-detail")
        app.buttons["Edit"].tap()
        XCTAssertEqual(app.textFields["business-field-name"].value as? String, "Cedar Labs")
        app.buttons["Cancel"].tap()
        try tap("Delete account", in: app)
        app.buttons["Delete"].tap()
        XCTAssertTrue(app.navigationBars["Accounts"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Finance"].tap()
        XCTAssertTrue(app.buttons["business-create"].waitForExistence(timeout: 5))
        app.buttons["business-create"].tap()
        app.textFields["business-field-vendor_name"].tap()
        app.textFields["business-field-vendor_name"].typeText("Workshop supplies")
        XCTAssertFalse(app.buttons["business-save"].isEnabled)
        let amount = try visible("business-field-total_amount_value", in: app)
        amount.tap()
        amount.typeText("142.75")
        capture(app, "ios-invoice-create")
        app.buttons["business-save"].tap()
        try tap("Workshop supplies", in: app)
        app.buttons["Edit"].tap()
        XCTAssertEqual(app.textFields["business-field-vendor_name"].value as? String, "Workshop supplies")
        app.buttons["Cancel"].tap()
        try tap("Delete invoice", in: app)
        app.buttons["Delete"].tap()
        XCTAssertTrue(app.navigationBars["Finance"].waitForExistence(timeout: 5))
        try tap("business-item-invoice-2", in: app)
        XCTAssertFalse(app.buttons["Edit"].exists)
        XCTAssertFalse(app.buttons["Delete invoice"].exists)
        capture(app, "ios-invoice-imported")
    }

    func testFailedSaveRetainsDraftAndRestrictedFinanceInLargeDarkText() throws {
        let app = launch(["--dark", "--large-text", "--fail-business-save", "--forbidden-finance"])
        defer { app.terminate() }
        app.buttons["business-create"].tap()
        app.textFields["business-field-title"].tap()
        app.textFields["business-field-title"].typeText("Keep this draft")
        app.buttons["business-save"].tap()
        XCTAssertTrue(app.staticTexts["Preview save failed. Your changes are still here."].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["business-field-title"].value as? String, "Keep this draft")
        app.swipeUp()
        capture(app, "ios-task-failed-save-large-dark")
        app.buttons["Cancel"].tap()
        app.buttons["Discard changes"].tap()
        app.tabBars.buttons["Finance"].tap()
        XCTAssertTrue(app.staticTexts["Access required"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["business-create"].exists)
        capture(app, "ios-finance-forbidden-large-dark")
    }

    private func launch(_ arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "dev.tuist.atlas.settings-preview")
        app.launchArguments = ["--workspace"] + arguments
        app.launch()
        XCTAssertTrue(app.buttons["business-create"].waitForExistence(timeout: 10))
        return app
    }

    private func visible(_ id: String, in app: XCUIApplication) throws -> XCUIElement {
        for _ in 0..<8 {
            let elements = app.descendants(matching: .any).matching(identifier: id).allElementsBoundByIndex
            if let element = elements.first(where: \.isHittable) { return element }
            app.swipeUp()
        }
        return try XCTUnwrap(nil as XCUIElement?, "Missing control: \(id)")
    }

    private func tap(_ id: String, in app: XCUIApplication) throws {
        try visible(id, in: app).tap()
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
