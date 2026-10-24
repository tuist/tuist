import XCTest

final class AdaptiveSignInTests: XCTestCase {
    @MainActor
    func test_signInActionsRemainReachableAfterRotation() {
        let app = XCUIApplication()
        app.launch()
        defer { XCUIDevice.shared.orientation = .portrait }

        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft, .landscapeRight, .portrait] {
            XCUIDevice.shared.orientation = orientation
            assertSignInActionsAreReachable(in: app)
        }
    }

    @MainActor
    func test_signInActionsRemainReachableWithLargeText() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL",
        ]
        app.launch()
        assertSignInActionsAreReachable(in: app)
    }

    @MainActor
    private func assertSignInActionsAreReachable(in app: XCUIApplication) {
        let signIn = app.buttons["Sign in with Tuist"]
        XCTAssertTrue(signIn.waitForExistence(timeout: 30))
        let scrollView = app.scrollViews.containing(.button, identifier: "Sign in with Tuist").firstMatch
        let selfHosted = app.buttons["Self-hosted server"]
        for _ in 0 ..< 10 {
            if selfHosted.isHittable { break }
            scrollView.swipeUp()
        }
        XCTAssertTrue(selfHosted.isHittable)
        selfHosted.tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        app.alerts.buttons["Cancel"].tap()

        for _ in 0 ..< 10 {
            if signIn.isHittable { break }
            scrollView.swipeDown()
        }
        XCTAssertTrue(signIn.isHittable)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
