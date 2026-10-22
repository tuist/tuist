import XCTest

final class AtlasNavigationUITests: XCTestCase {
    private let recordID = "123e4567-e89b-12d3-a456-426614174000"

    @MainActor func testColdRecordLinkOpensBeyondFirstPageAndBackLoadsList() {
        let app = launch(path: "tasks/\(recordID)")
        defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["Deep-linked task beyond the first page"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Opened directly by UUID."].exists)
        XCTAssertTrue(app.buttons["Edit"].waitForExistence(timeout: 5))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "ios-navigation-direct-record-preview"
        attachment.lifetime = .keepAlways
        add(attachment)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Tasks"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Review onboarding"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.tabBars.buttons.count, 5)
    }

    @MainActor func testHTTPSRecordLinkOpensNativeDetailWithBrowserEscape() {
        let app = launch(path: "tasks/\(recordID)", web: true)
        defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["Deep-linked task beyond the first page"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Open in browser"].exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "ios-https-link-native-detail-preview"
        attachment.lifetime = .keepAlways
        add(attachment)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Tasks"].waitForExistence(timeout: 5))
    }

    @MainActor func testMissingRecordHasRetryAndBackWithoutMutationControls() {
        let app = launch(path: "tasks/00000000-0000-0000-0000-000000000000")
        defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["Record unavailable"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["This record could not be found."].exists)
        XCTAssertFalse(app.buttons["Edit"].exists)
        XCTAssertTrue(app.buttons["navigation-retry"].exists)
        app.buttons["navigation-retry"].tap()
        XCTAssertTrue(app.staticTexts["Record unavailable"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Tasks"].waitForExistence(timeout: 5))
    }

    @MainActor func testRevokedRecordAccessClearsCachedListAndAllowsRetry() {
        let app = XCUIApplication(bundleIdentifier: "dev.tuist.atlas.settings-preview")
        app.launchArguments = ["--workspace", "--deep-links", "--revoke-record-access", "--resume-destination",
                               "https://atlas.example.org/open/tasks/\(recordID)"]
        app.launch()
        defer { app.terminate() }
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(app.staticTexts["Review onboarding"].waitForExistence(timeout: 5))
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.staticTexts["Record unavailable"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Your Atlas role does not allow this action."].exists)
        XCTAssertFalse(app.buttons["Edit"].exists)
        app.buttons["navigation-retry"].tap()
        XCTAssertTrue(app.staticTexts["Record unavailable"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["Access required"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Review onboarding"].exists)
        XCTAssertFalse(app.buttons["business-create"].exists)
    }

    @MainActor func testTimeOffLinkHasNativeBackToBrowse() {
        let app = launch(path: "time-off")
        defer { app.terminate() }
        XCTAssertTrue(app.navigationBars["Time off"].waitForExistence(timeout: 10))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Browse"].waitForExistence(timeout: 5))
    }

    @MainActor func testProfileLinkReturnsFromAppearanceWithoutResettingTheme() throws {
        let app = XCUIApplication(bundleIdentifier: "dev.tuist.atlas.settings-preview")
        app.launchArguments = ["--workspace", "--resume-destination", "https://atlas.example.org/open/profile"]
        app.launch()
        defer { app.terminate() }
        XCUIDevice.shared.orientation = .portrait
        app.tabBars.buttons["Profile"].tap()
        try app.visibleElement("profile-appearance").tap()
        try app.visibleElement("theme-pulse").tap()
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.navigationBars["Profile"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Open in browser"].exists)
        try app.visibleElement("profile-appearance").tap()
        XCTAssertEqual(try app.visibleElement("theme-pulse").value as? String, "Selected")
    }

    @MainActor func testCrossServerLinkShowsExplanationWithoutNavigating() {
        let app = launch(path: "accounts", server: "other.example.org")
        defer { app.terminate() }
        XCTAssertTrue(app.alerts["Atlas link"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.alerts.staticTexts[
            "This link belongs to a different Atlas server. Sign in to that server and open the link again."
        ].exists)
        app.alerts.buttons["OK"].tap()
        XCTAssertTrue(app.navigationBars["Tasks"].exists)
    }

    @MainActor func testWarmRecordLinkReplacesAnExistingDetailAndBackReturnsToList() {
        exerciseWarmRecordLink("dev.tuist.atlas://navigate/tasks/\(recordID)?server=https%3A%2F%2Fatlas.example.org")
    }

    @MainActor func testWarmHTTPSRecordLinkReplacesAnExistingDetail() {
        exerciseWarmRecordLink("https://atlas.example.org/open/tasks/\(recordID)?token=ignored#detail")
    }

    @MainActor private func exerciseWarmRecordLink(_ url: String) {
        let app = XCUIApplication(bundleIdentifier: "dev.tuist.atlas.settings-preview")
        app.launchArguments = ["--workspace", "--deep-links", "--resume-destination", url]
        app.launch()
        defer { app.terminate() }
        XCUIDevice.shared.orientation = .portrait
        let row = app.descendants(matching: .any)["business-item-task-1"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(app.navigationBars["Task"].waitForExistence(timeout: 5))
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.staticTexts["Deep-linked task beyond the first page"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.alerts["Atlas link"].exists)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Tasks"].waitForExistence(timeout: 5))
    }

    @MainActor func testWarmLinkCannotDiscardAISetupDraft() {
        let app = XCUIApplication(bundleIdentifier: "dev.tuist.atlas.settings-preview")
        app.launchArguments = ["--workspace", "--resume-destination",
                               "dev.tuist.atlas://navigate/accounts?server=https%3A%2F%2Fatlas.example.org"]
        app.launch()
        defer { app.terminate() }
        XCUIDevice.shared.orientation = .portrait
        app.tabBars.buttons["Profile"].tap()
        app.buttons["ai-account-claude"].tap()
        let token = app.secureTextFields["claude-token"]
        XCTAssertTrue(token.waitForExistence(timeout: 5))
        token.tap()
        token.typeText("preview-only")
        XCTAssertFalse(app.tabBars.buttons["Tasks"].isHittable)
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.alerts["Atlas link"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.alerts.staticTexts["Finish or discard your changes, then open the link again."].exists)
        app.alerts.buttons["OK"].tap()
        XCTAssertTrue(token.exists)
        XCTAssertEqual((token.value as? String)?.count, "preview-only".count)
        XCTAssertTrue(app.navigationBars["Claude"].exists)
    }

    @MainActor private func launch(path: String, server: String = "atlas.example.org", web: Bool = false) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "dev.tuist.atlas.settings-preview")
        let url = web ? "https://\(server)/open/\(path)" : "dev.tuist.atlas://navigate/\(path)?server=https%3A%2F%2F\(server)"
        app.launchArguments = ["--workspace", "--deep-links", "--business-pagination", "--destination", url]
        app.launch()
        XCUIDevice.shared.orientation = .portrait
        return app
    }
}
