import XCTest

/// Launches a fresh app before every test and terminates it after, the way most UI suites do.
class ShopUITestCase: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    override func tearDown() {
        app.terminate()
        super.tearDown()
    }

    func relaunch() {
        app.terminate()
        app.launch()
    }
}
