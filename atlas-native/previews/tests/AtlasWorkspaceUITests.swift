import XCTest

final class AtlasWorkspaceUITests: XCTestCase {
    @MainActor func testProfileDescriptionSaveAndFailureDraftRetention() throws {
        for failing in [false, true] {
            let app = launch(arguments: failing ? ["--fail-business-save"] : [])
            defer { app.terminate() }
            app.tabBars.buttons["Profile"].tap()
            try tap("profile-edit-description", in: app)
            let field = app.textViews["profile-description"]
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            field.tap()
            field.typeText("Engineering lead. Curious; concise answers please.")
            app.buttons["profile-save"].tap()
            if failing {
                XCTAssertTrue(app.staticTexts["Preview save failed. Your draft is still here."].waitForExistence(timeout: 5))
                XCTAssertEqual(field.value as? String, "Engineering lead. Curious; concise answers please.")
                attach(app, "ios-profile-description-failed-draft-preview")
                app.buttons["Cancel"].tap()
                app.buttons["Discard changes"].tap()
                XCTAssertTrue(app.buttons["profile-edit-description"].waitForExistence(timeout: 5))
                XCTAssertTrue(app.buttons["Tell Pip about yourself"].exists)
            } else {
                XCTAssertTrue(app.buttons["profile-edit-description"].waitForExistence(timeout: 5))
                XCTAssertTrue(app.staticTexts["Engineering lead. Curious; concise answers please."].exists)
                attach(app, "ios-profile-description-saved-preview")
                try tap("profile-edit-description", in: app)
                XCTAssertEqual(field.value as? String, "Engineering lead. Curious; concise answers please.")
                app.buttons["Cancel"].tap()
            }
            app.terminate()
        }
    }

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
        XCTAssertTrue(app.navigationBars["Orbit"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.tabBars.buttons["Orbit"].exists)
        XCTAssertEqual(app.tabBars.buttons.count, 5)
        XCTAssertFalse(app.tabBars.buttons["More"].exists)
        XCTAssertTrue(app.buttons["thread-01922cc0-0000-7000-8000-000000000001"].waitForExistence(timeout: 5))
        attach(app, "ios-workspace-threads-preview")
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

    @MainActor func testEmptyPresenceKeepsNativeRootAndDetailNavigation() throws {
        let app = launch(arguments: ["--nobody-here"])
        defer { app.terminate() }
        app.tabBars.buttons["Accounts"].tap()
        XCTAssertTrue(app.buttons["business-item-account-1"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["also-here"].exists)
        XCTAssertTrue(app.buttons["Open in browser"].isHittable)
        attach(app, "ios-workspace-accounts-nobody-here-preview")
        try tap("business-item-account-1", in: app)
        XCTAssertTrue(app.navigationBars["Account"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["also-here"].exists)
        XCTAssertTrue(app.navigationBars.buttons.element(boundBy: 0).isHittable)
        attach(app, "ios-workspace-account-detail-nobody-here-preview")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Accounts"].waitForExistence(timeout: 5))
    }

    @MainActor func testPresenceUsesNativeToolbarWithoutCoveringNavigation() throws {
        for arguments in [[], ["--dark", "--large-text"]] {
            let app = launch(arguments: arguments + ["--delayed-business"])
            defer { app.terminate() }
            for title in ["Accounts", "Finance", "Profile", "Accounts"] {
                app.tabBars.buttons[title].tap()
                let indicator = app.buttons["also-here"]
                XCTAssertTrue(indicator.waitForExistence(timeout: 5))
                XCTAssertTrue(indicator.isHittable)
                let heading = app.navigationBars[title].staticTexts[title]
                XCTAssertGreaterThan(heading.frame.height, 30)
                XCTAssertLessThanOrEqual(indicator.frame.maxY, heading.frame.minY)
                XCTAssertLessThanOrEqual(indicator.frame.maxX, app.buttons["Open in browser"].frame.minX)
                // Native toolbar accessibility frames exclude the extended 44pt touch target.
                app.coordinate(withNormalizedOffset: .zero)
                    .withOffset(CGVector(dx: indicator.frame.midX, dy: indicator.frame.midY + 21)).tap()
                XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Alex Morgan"))
                    .firstMatch.waitForExistence(timeout: 5))
                attach(app, "ios-workspace-\(title.lowercased())-presence-menu-preview")
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.7)).tap()
            }
            try tap("business-item-account-1", in: app)
            XCTAssertTrue(app.navigationBars["Account"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["also-here"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["also-here"].isHittable)
            XCTAssertTrue(app.navigationBars.buttons.element(boundBy: 0).isHittable)
            app.tabBars.buttons["Profile"].tap()
            try tap("profile-appearance", in: app)
            XCTAssertTrue(app.navigationBars["Appearance"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["also-here"].exists)
            app.navigationBars.buttons.element(boundBy: 0).tap()
            XCTAssertTrue(app.navigationBars["Profile"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["also-here"].waitForExistence(timeout: 5))
            app.terminate()
        }
    }

    @MainActor func testReturningToOrbitRetainsLoadedThreadsUntilExplicitRefresh() throws {
        let app = launch(arguments: ["--fail-orbit-refresh"])
        defer { app.terminate() }
        let conversation = app.buttons["thread-01922cc0-0000-7000-8000-000000000001"]
        XCTAssertTrue(conversation.waitForExistence(timeout: 5))
        for title in ["Accounts", "Finance", "Browse", "Profile", "Orbit"] {
            app.tabBars.buttons[title].tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5))
        }
        let failure = app.staticTexts["Preview refresh failed. Loaded threads are retained."]
        XCTAssertFalse(failure.waitForExistence(timeout: 2))
        XCTAssertTrue(conversation.exists)
        attach(app, "ios-workspace-orbit-retained-preview")
        app.scrollContent(up: false)
        XCTAssertTrue(failure.waitForExistence(timeout: 5))
        XCTAssertTrue(conversation.exists)
        attach(app, "ios-workspace-orbit-failed-refresh-preview")
    }

    @MainActor func testTabsStartAtTopAfterDelayedDataArrives() throws {
        let app = launch(arguments: ["--delayed-business"])
        defer { app.terminate() }
        for title in ["Orbit", "Accounts", "Finance", "Browse", "Profile"] {
            app.tabBars.buttons[title].tap()
            switch title {
            case "Orbit": XCTAssertTrue(app.buttons["thread-01922cc0-0000-7000-8000-000000000001"].waitForExistence(timeout: 5))
            case "Accounts": XCTAssertTrue(app.staticTexts["Northstar"].waitForExistence(timeout: 5))
            case "Finance": XCTAssertTrue(app.descendants(matching: .any)["finance-available-cash"].waitForExistence(timeout: 5))
            case "Profile": XCTAssertTrue(app.staticTexts["Taylor Morgan"].waitForExistence(timeout: 5))
            default: XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5))
            }
            let heading = app.navigationBars[title].staticTexts[title]
            XCTAssertGreaterThan(heading.frame.height, 30, "\(title) should initially have its expanded title")
            attach(app, "ios-workspace-\(title.lowercased())-initial-top-preview")
        }
    }

    @MainActor func testNativeSearchInDarkAccessibilityText() throws {
        let app = launch(arguments: ["--dark", "--large-text"])
        defer { app.terminate() }
        XCTAssertTrue(app.navigationBars["Orbit"].waitForExistence(timeout: 10))
        attach(app, "ios-workspace-threads-large-dark-preview")
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

    @MainActor func testSocialScreenshotsWithFictionalBusinessData() throws {
        for mode in ["light", "dark"] {
            let app = launch(arguments: ["--social-screenshots"] + (mode == "dark" ? ["--dark"] : []))
            defer { app.terminate() }
            let conversation = app.buttons["thread-01922cc0-0000-7000-8000-000000000001"]
            XCTAssertTrue(conversation.waitForExistence(timeout: 10))
            XCTAssertTrue(app.staticTexts["Next week’s customer calls"].exists)
            attach(app, "atlas-social-orbit-\(mode)")
            conversation.tap()
            XCTAssertTrue(app.textFields["thread-composer"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["Start with Northstar: it has the nearest deadline."].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["Start with Northstar: it has the nearest deadline."].isHittable)
            attach(app, "atlas-social-pip-\(mode)")
            app.navigationBars.buttons.element(boundBy: 0).tap()
            app.tabBars.buttons["Accounts"].tap()
            XCTAssertTrue(app.staticTexts["Harbor Labs"].waitForExistence(timeout: 5))
            attach(app, "atlas-social-accounts-\(mode)")
            app.tabBars.buttons["Finance"].tap()
            XCTAssertTrue(app.descendants(matching: .any)["finance-available-cash"].waitForExistence(timeout: 5))
            attach(app, "atlas-social-finance-\(mode)")
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
