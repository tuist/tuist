import XCTest

final class LogInUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func test_launch_shows_sign_in_options() {
        let app = launchApp()
        XCTAssertTrue(app.staticTexts["log-in-title"].waitForExistence(timeout: 30))

        for identifier in [
            "sign-in-tuist",
            "sign-in-apple",
            "sign-in-google",
            "sign-in-github",
            "sign-in-self-hosted",
        ] {
            let button = app.buttons[identifier]
            XCTAssertTrue(button.exists, "Missing \(identifier)")
            XCTAssertTrue(button.isHittable, "\(identifier) is not hittable")
        }
    }

    @MainActor
    func test_self_hosted_prompt_accepts_only_https_urls() {
        let app = launchApp()
        let selfHosted = app.buttons["sign-in-self-hosted"]
        XCTAssertTrue(selfHosted.waitForExistence(timeout: 30))
        selfHosted.tap()

        let alert = app.alerts["Self-hosted"]
        XCTAssertTrue(alert.waitForExistence(timeout: 10))
        let urlField = alert.textFields["self-hosted-server-url"]
        let signIn = alert.buttons["Sign in"]
        XCTAssertTrue(urlField.exists)
        XCTAssertFalse(signIn.isEnabled)

        urlField.tap()
        urlField.typeText("http://tuist.example.com")
        XCTAssertFalse(signIn.isEnabled)

        urlField.clearText()
        urlField.typeText("https://tuist.example.com")
        XCTAssertTrue(signIn.isEnabled)
    }

    @MainActor
    func test_cancelling_self_hosted_prompt_returns_to_sign_in() {
        let app = launchApp()
        let selfHosted = app.buttons["sign-in-self-hosted"]
        XCTAssertTrue(selfHosted.waitForExistence(timeout: 30))
        selfHosted.tap()

        let alert = app.alerts["Self-hosted"]
        XCTAssertTrue(alert.waitForExistence(timeout: 10))
        alert.buttons["Cancel"].tap()

        XCTAssertTrue(alert.waitForNonExistence(timeout: 10))
        XCTAssertTrue(app.buttons["sign-in-tuist"].isHittable)
        XCTAssertTrue(selfHosted.isHittable)
    }

    @MainActor
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()
        return app
    }
}

extension XCUIElement {
    fileprivate func clearText() {
        guard let value = value as? String, !value.isEmpty else { return }
        typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count))
    }
}
