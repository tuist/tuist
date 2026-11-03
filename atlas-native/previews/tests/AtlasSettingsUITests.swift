import XCTest

@MainActor
final class AtlasSettingsUITests: XCTestCase {
    func testCodingRepositoryDefaultsAndConversationOverride() {
        for arguments in [[String](), ["--dark", "--large-text"]] {
            let app = XCUIApplication(bundleIdentifier: "dev.tuist.atlas.settings-preview")
            let mode = arguments.isEmpty ? "light" : "dark-large"
            app.launchArguments = ["--coding"] + arguments
            app.launch()
            XCUIDevice.shared.orientation = .portrait
            let repository = app.buttons["coding-default-repository"]
            XCTAssertTrue(repository.waitForExistence(timeout: 10))
            capture("ios-coding-settings-\(mode)-preview", app: app)
            tap(repository, in: app)
            XCTAssertTrue(app.buttons["acme/server"].waitForExistence(timeout: 5))
            let search = app.searchFields["Find a repository"]
            XCTAssertTrue(search.waitForExistence(timeout: 5))
            XCTAssertLessThan(search.frame.maxY, app.buttons["acme/mobile"].frame.minY)
            XCTAssertGreaterThanOrEqual(app.buttons["acme/mobile"].frame.height, 44)
            capture("ios-coding-repositories-\(mode)-preview", app: app)
            search.tap()
            search.typeText("no-such-repo")
            XCTAssertTrue(app.staticTexts["No repositories found"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["acme/mobile"].exists)
            capture("ios-coding-repositories-empty-\(mode)-preview", app: app)
            search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "no-such-repo".count) + "server")
            XCTAssertTrue(app.buttons["acme/server"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["acme/mobile"].exists)
            capture("ios-coding-repositories-search-\(mode)-preview", app: app)
            app.buttons["acme/server"].tap()
            tap(app.buttons["coding-save"], in: app)
            XCTAssertTrue(app.staticTexts["Repository settings saved. Existing conversations are unchanged."].waitForExistence(timeout: 5))
            app.terminate()

            app.launchArguments = ["--workspace", "--destination",
                "https://atlas.example.org/open/orbit/01922cc0-0000-7000-8000-000000000001"] + arguments
            app.launch()
            let environment = app.buttons["thread-environment"]
            XCTAssertTrue(environment.waitForExistence(timeout: 10))
            environment.tap()
            let picker = app.buttons["thread-repository"]
            XCTAssertTrue(picker.waitForExistence(timeout: 5))
            picker.tap()
            XCTAssertTrue(app.buttons["acme/mobile"].waitForExistence(timeout: 5))
            XCTAssertGreaterThanOrEqual(app.buttons["acme/mobile"].frame.height, 44)
            capture("ios-thread-repositories-\(mode)-preview", app: app)
            app.buttons["acme/mobile"].tap()
            let project = app.buttons["Example project"]
            tap(project, in: app)
            expectation(for: NSPredicate(format: "value == 'Selected'"), evaluatedWith: project)
            waitForExpectations(timeout: 5)
            tap(picker, in: app, up: false)
            XCTAssertTrue(app.buttons["acme/server"].waitForExistence(timeout: 5))
            app.buttons["acme/server"].tap()
            let noCheckout = app.descendants(matching: .any).matching(identifier: "checkout-unavailable").firstMatch
            reveal(noCheckout, in: app)
            XCTAssertEqual(app.buttons["Atlas server"].value as? String, "Selected")
            XCTAssertFalse(project.exists)
            capture("ios-coding-no-checkout-\(mode)-preview", app: app)
            app.terminate()
        }
    }

    func testPersonalConnections() {
        for arguments in [[String](), ["--dark", "--large-text"]] {
            let app = XCUIApplication(bundleIdentifier: "dev.tuist.atlas.settings-preview")
            app.launchArguments = ["--workspace"] + arguments
            app.launch()
            XCUIDevice.shared.orientation = .portrait
            XCTAssertTrue(app.tabBars.buttons["Profile"].waitForExistence(timeout: 10))
            app.tabBars.buttons["Profile"].tap()
            tap(app.buttons["profile-connections"], in: app)
            XCTAssertTrue(app.navigationBars["Connections"].waitForExistence(timeout: 10))
            let github = app.buttons["connection-github"]
            XCTAssertTrue(github.waitForExistence(timeout: 10))
            XCTAssertGreaterThanOrEqual(github.frame.height, 44)
            XCTAssertTrue(github.isEnabled)
            capture(arguments.isEmpty ? "ios-connections-preview" : "ios-connections-dark-large-preview", app: app)
            XCTAssertFalse(app.buttons["Disconnect Slack"].exists)
            tap(github, in: app)
            XCTAssertTrue(app.navigationBars["GitHub"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["Connect GitHub"].exists)
            XCTAssertFalse(app.buttons["Disconnect GitHub"].exists)
            capture(arguments.isEmpty ? "ios-connection-github-preview" : "ios-connection-github-dark-large-preview", app: app)
            app.navigationBars["GitHub"].buttons.element(boundBy: 0).tap()
            tap(app.buttons["connection-slack"], in: app)
            XCTAssertTrue(app.navigationBars["Slack"].waitForExistence(timeout: 5))
            let disconnect = app.buttons["Disconnect Slack"]
            XCTAssertGreaterThanOrEqual(app.buttons["Reconnect Slack"].frame.height, 44)
            capture(arguments.isEmpty ? "ios-connection-slack-preview" : "ios-connection-slack-dark-large-preview", app: app)
            tap(disconnect, in: app)
            XCTAssertTrue(app.buttons["Disconnect"].waitForExistence(timeout: 5))
            if app.buttons["Cancel"].exists {
                app.buttons["Cancel"].tap()
            } else {
                // iOS 26 presents a popover; tapping outside is its native Cancel action.
                let dismiss = app.otherElements["PopoverDismissRegion"]
                XCTAssertTrue(dismiss.exists)
                dismiss.tap()
            }
            XCTAssertTrue(app.buttons["Reconnect Slack"].exists)
            app.navigationBars["Slack"].buttons.element(boundBy: 0).tap()
            tap(app.buttons["connection-google"], in: app)
            XCTAssertTrue(app.navigationBars["Google"].waitForExistence(timeout: 5))
            capture(arguments.isEmpty ? "ios-connection-google-preview" : "ios-connection-google-dark-large-preview", app: app)
            tap(app.buttons["Reconnect Google"], in: app)
            XCTAssertTrue(app.staticTexts["Preview only. No accounts are changed."].waitForExistence(timeout: 5))
            app.navigationBars["Google"].buttons.element(boundBy: 0).tap()
            app.navigationBars["Connections"].buttons.element(boundBy: 0).tap()
            XCTAssertTrue(app.tabBars.buttons["Profile"].waitForExistence(timeout: 5))
            app.terminate()
        }
    }

    func testUnavailableConnectionsExplainServerSetup() {
        for arguments in [[String](), ["--dark", "--large-text"]] {
            let app = XCUIApplication(bundleIdentifier: "dev.tuist.atlas.settings-preview")
            app.launchArguments = ["--connections", "--unavailable-connections"] + arguments
            app.launch()
            XCUIDevice.shared.orientation = .portrait
            let github = app.buttons["connection-github"]
            XCTAssertTrue(github.waitForExistence(timeout: 10))
            capture("ios-connections-unavailable-\(arguments.isEmpty ? "light" : "dark-large")-preview", app: app)
            github.tap()
            XCTAssertTrue(app.navigationBars["GitHub"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["Connect GitHub"].exists)
            XCTAssertTrue(app.staticTexts["An administrator needs to configure GitHub authorization before you can connect."].exists)
            capture("ios-connection-unavailable-\(arguments.isEmpty ? "light" : "dark-large")-preview", app: app)
            app.terminate()
        }
    }

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
