import XCTest

final class AtlasWorkspaceUITests: XCTestCase {
    @MainActor func testThemeCatalogLightDarkAndPersistence() throws {
        let app = launch()
        defer { app.terminate() }
        app.tabBars.buttons["Profile"].tap()
        try tap("profile-appearance", in: app)
        XCTAssertTrue(app.navigationBars["Appearance"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["also-here"].exists)
        attach(app, "ios-theme-chooser")
        for theme in ["pulse", "berlin", "habibi", "amrit", "pelotas", "branik"] {
            let choice = try app.visibleElement("theme-\(theme)", up: false)
            XCTAssertGreaterThanOrEqual(choice.frame.height, 44)
            choice.tap()
            XCTAssertEqual(choice.value as? String, "Selected")
            for mode in ["Light", "Dark"] {
                let picker = try app.visibleElement("appearance-mode", up: mode == "Light")
                picker.buttons[mode].tap()
                XCTAssertTrue(picker.buttons[mode].isSelected)
                let preview = try app.visibleElement("appearance-preview")
                app.scrollContent()
                XCTAssertLessThanOrEqual(preview.frame.maxY, app.tabBars.firstMatch.frame.minY)
                attach(app, "ios-theme-\(theme)-\(mode.lowercased())")
            }
        }
        app.terminate()
        app.launchArguments = ["--workspace", "--keep-appearance"]
        app.launch()
        app.tabBars.buttons["Profile"].tap()
        try tap("profile-appearance", in: app)
        let selected = try app.visibleElement("theme-branik")
        XCTAssertEqual(selected.value as? String, "Selected")
        let picker = try app.visibleElement("appearance-mode")
        XCTAssertTrue(picker.buttons["Dark"].isSelected)
    }

    @MainActor func testOlderServerAppearanceWithAccessibilityText() throws {
        let app = launch(arguments: ["--old-server", "--dark", "--large-text"])
        defer { app.terminate() }
        app.tabBars.buttons["Profile"].tap()
        try tap("profile-appearance", in: app)
        _ = try app.visibleElement("theme-atlas")
        XCTAssertFalse(app.buttons["theme-pulse"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["also-here"].exists)
        attach(app, "ios-theme-older-server-large-dark")
        let preview = try app.visibleElement("appearance-preview")
        app.scrollContent()
        XCTAssertLessThanOrEqual(preview.frame.maxY, app.tabBars.firstMatch.frame.minY)
        attach(app, "ios-theme-older-server-preview-large-dark")
    }

    @MainActor func testStableTabsNativeBrowseAndProfile() throws {
        let app = launch()
        defer { app.terminate() }
        XCTAssertTrue(app.navigationBars["Conversations"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.tabBars.buttons.count, 5)
        XCTAssertFalse(app.tabBars.buttons["More"].exists)
        XCTAssertTrue(app.buttons["conversations-private"].waitForExistence(timeout: 5))
        attach(app, "ios-workspace-conversations-preview")
        app.tabBars.buttons["Browse"].tap()
        try tap("workspace-section-tasks", in: app)
        XCTAssertTrue(app.buttons["business-item-task-1"].waitForExistence(timeout: 5))
        XCTAssertGreaterThan(app.navigationBars["Tasks"].staticTexts["Tasks"].frame.height, 30)
        attach(app, "ios-workspace-tasks")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.tabBars.buttons["Accounts"].tap()
        XCTAssertTrue(app.staticTexts["Northstar"].waitForExistence(timeout: 5))
        XCTAssertGreaterThan(app.navigationBars["Accounts"].staticTexts["Accounts"].frame.height, 30)
        attach(app, "ios-workspace-accounts")
        app.tabBars.buttons["Finance"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["finance-available-cash"].waitForExistence(timeout: 5))
        XCTAssertGreaterThan(app.navigationBars["Finance"].staticTexts["Finance"].frame.height, 30)
        attach(app, "ios-workspace-finance")
        _ = try app.visibleElement("finance-cash-flow")
        attach(app, "ios-workspace-finance-cash-flow")
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
        XCTAssertTrue(app.navigationBars["Conversations"].waitForExistence(timeout: 10))
        attach(app, "ios-workspace-conversations-large-dark-preview")
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

    @MainActor func testRichAccountDetailsAndContactDrilldown() throws {
        let app = launch()
        defer { app.terminate() }
        app.tabBars.buttons["Accounts"].tap()
        try tap("business-item-account-1", in: app)
        XCTAssertTrue(app.navigationBars["Account"].waitForExistence(timeout: 5))
        let contacts = try app.visibleElement("account-related-full_name-Contacts")
        contacts.tap()
        try tap("Jordan Reed", in: app)
        XCTAssertTrue(app.navigationBars["Contacts"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["jordan@northstar.example.org"].exists)
        attach(app, "ios-account-contact")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        _ = try app.visibleElement("billing@northstar.example.org")
        attach(app, "ios-account-billing")
    }

    @MainActor func testFinanceDoesNotShowMisleadingZeroTotalsWhenDataIsUnavailable() throws {
        for (argument, message) in [
            ("--empty-finance", "No connected bank accounts yet."),
            ("--missing-finance-fx", "Currency conversion unavailable"),
            ("--legacy-finance", "Update your Atlas server to see cash flow in one reporting currency.")
        ] {
            let app = launch(arguments: [argument, "--dark", "--large-text"])
            app.tabBars.buttons["Finance"].tap()
            XCTAssertTrue(app.staticTexts[message].waitForExistence(timeout: 5))
            XCTAssertFalse(app.descendants(matching: .any)["finance-available-cash"].exists)
            XCTAssertFalse(app.descendants(matching: .any)["finance-cash-flow"].exists)
            attach(app, "ios-finance\(argument)-large-dark")
            app.terminate()
        }
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
