import XCTest

class AppUITest: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testAppLaunchesAndPresentsRootView() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(
            app.otherElements["RootView"].waitForExistence(timeout: 10),
            "Expected the root view to be present after launch"
        )
        XCTAssertEqual(app.state, .runningForeground)
    }
}
