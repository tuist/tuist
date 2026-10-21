import XCTest

@MainActor
final class AtlasSettingsUITests: XCTestCase {
    func testSettingsAndAccountForms() {
        exerciseSettings(launch())
    }

    func testSettingsAndAccountFormsInDarkMode() {
        exerciseSettings(launch(["--dark"]), suffix: "-dark")
    }

    func testSettingsAndAccountFormsWithLargeText() {
        exerciseSettings(launch(["--large-text"]), suffix: "-large-text")
    }

    func testSettingsAndAccountFormsInLandscape() {
        defer { XCUIDevice.shared.orientation = .portrait }
        exerciseSettings(launch(orientation: .landscapeLeft), suffix: "-landscape")
    }

    func testLateSaveDoesNotDismissANewerForm() {
        let app = launch(["--slow-save"])
        tap(app.staticTexts["Claude"], in: app)
        app.secureTextFields["claude-token"].tap()
        app.secureTextFields["claude-token"].typeText("preview-only")
        app.buttons["Save connection"].tap()
        app.navigationBars["Claude"].buttons.element(boundBy: 0).tap()
        tap(app.staticTexts["Claude"], in: app)
        app.secureTextFields["claude-token"].tap()
        app.secureTextFields["claude-token"].typeText("new-preview-only")
        let saved = expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: app.buttons["Save connection"])
        wait(for: [saved], timeout: 15)
        XCTAssertTrue(app.navigationBars["Claude"].exists)
        XCTAssertTrue(app.secureTextFields["claude-token"].exists)
    }

    private func launch(_ arguments: [String] = [], orientation: UIDeviceOrientation = .portrait) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "dev.tuist.atlas.settings-preview")
        app.launchArguments = arguments
        app.launch()
        XCUIDevice.shared.orientation = orientation
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))
        return app
    }

    private func exerciseSettings(_ app: XCUIApplication, suffix: String = "") {
        XCTAssertTrue(app.staticTexts["Not connected"].firstMatch.waitForExistence(timeout: 10))
        capture("ios-settings" + suffix, app: app)
        tap(app.staticTexts["Claude"], in: app)
        XCTAssertTrue(app.secureTextFields["claude-token"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Save connection"].isEnabled)
        capture("ios-claude" + suffix, app: app)
        tap(app.buttons["How to get a token"], in: app)
        let install = app.descendants(matching: .any).matching(identifier: "claude-install-link").firstMatch
        reveal(install, in: app)
        XCTAssertGreaterThanOrEqual(install.frame.height, 44)
        capture("ios-claude-help" + suffix, app: app)
        let linkFrame = install.frame
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(
            dx: linkFrame.minX + linkFrame.width * 0.95,
            dy: linkFrame.minY + linkFrame.height * 0.1
        )).tap()
        XCTAssertTrue(app.alerts["Link preview"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.alerts.staticTexts["https://code.claude.com/docs/en/setup"].exists)
        app.alerts.buttons["Done"].tap()
        tap(app.buttons["How to get a token"], in: app, up: false)
        tap(app.secureTextFields["claude-token"], in: app, up: false)
        app.secureTextFields["claude-token"].typeText("preview-only")
        XCTAssertTrue(app.buttons["Save connection"].isEnabled)
        XCTAssertTrue(app.buttons["Save connection"].isHittable)
        XCTAssertGreaterThanOrEqual(app.buttons["Save connection"].frame.height, 44)
        capture("ios-claude-keyboard" + suffix, app: app)
        app.navigationBars["Claude"].buttons.element(boundBy: 0).tap()
        tap(app.staticTexts["ChatGPT"], in: app)
        XCTAssertTrue(app.buttons["Sign in with ChatGPT"].waitForExistence(timeout: 5))
        app.buttons["Sign in with ChatGPT"].tap()
        XCTAssertTrue(app.staticTexts["chatgpt-device-code"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["chatgpt-device-code"].label, "Sign-in code")
        XCTAssertGreaterThanOrEqual(app.buttons["Cancel sign-in"].frame.height, 44)
        XCTAssertTrue(app.buttons["Cancel sign-in"].isHittable)
        capture("ios-chatgpt" + suffix, app: app)
        app.buttons["Cancel sign-in"].tap()
        XCTAssertTrue(app.buttons["Sign in with ChatGPT"].waitForExistence(timeout: 5))
    }

    private func tap(_ element: XCUIElement, in app: XCUIApplication, up: Bool = true) {
        reveal(element, in: app, up: up)
        element.tap()
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication, up: Bool = true) {
        for _ in 0..<8 {
            let top = app.navigationBars.firstMatch.frame.maxY
            let bottom = app.buttons["Save connection"].exists ? app.buttons["Save connection"].frame.minY - 12 : app.frame.maxY - 32
            if element.exists && element.isHittable && element.frame.minY >= top && element.frame.maxY <= bottom { return }
            app.scrollContent(up: element.exists ? element.frame.minY >= top : up)
        }
        XCTFail("Control did not become visible: \(element.identifier)")
    }

    private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
