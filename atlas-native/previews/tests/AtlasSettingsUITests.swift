import XCTest

@MainActor
final class AtlasSettingsUITests: XCTestCase {
    func testSettingsAndAccountForms() {
        let app = XCUIApplication(bundleIdentifier: "dev.tuist.atlas.settings-preview")
        app.launch()
        exerciseSettings(app)
    }

    func testSettingsAndAccountFormsInDarkMode() {
        let app = XCUIApplication(bundleIdentifier: "dev.tuist.atlas.settings-preview")
        app.launchArguments = ["--dark"]
        app.launch()
        exerciseSettings(app, suffix: "-dark")
    }

    func testSettingsAndAccountFormsWithLargeText() {
        let app = XCUIApplication(bundleIdentifier: "dev.tuist.atlas.settings-preview")
        app.launchArguments = ["--large-text"]
        app.launch()
        exerciseSettings(app, suffix: "-large-text")
    }

    private func exerciseSettings(_ app: XCUIApplication, suffix: String = "") {
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Not connected"].firstMatch.waitForExistence(timeout: 10))
        capture("ios-settings" + suffix, app: app)

        app.staticTexts["Claude"].tap()
        XCTAssertTrue(app.secureTextFields["claude-token"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Save connection"].isEnabled)
        capture("ios-claude" + suffix, app: app)
        app.buttons["How to get a token"].tap()
        XCTAssertTrue(app.staticTexts["claude setup-token"].waitForExistence(timeout: 5))
        capture("ios-claude-help" + suffix, app: app)
        app.buttons["How to get a token"].tap()
        app.secureTextFields["claude-token"].tap()
        app.secureTextFields["claude-token"].typeText("preview-only")
        XCTAssertTrue(app.buttons["Save connection"].isEnabled)
        app.navigationBars["Claude"].buttons.element(boundBy: 0).tap()

        app.staticTexts["ChatGPT"].tap()
        XCTAssertTrue(app.buttons["Sign in with ChatGPT"].waitForExistence(timeout: 5))
        app.buttons["Sign in with ChatGPT"].tap()
        XCTAssertTrue(app.staticTexts["DEMO-CODE"].waitForExistence(timeout: 5))
        capture("ios-chatgpt" + suffix, app: app)
        app.buttons["Cancel sign-in"].tap()
        XCTAssertTrue(app.buttons["Sign in with ChatGPT"].waitForExistence(timeout: 5))
    }

    private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
