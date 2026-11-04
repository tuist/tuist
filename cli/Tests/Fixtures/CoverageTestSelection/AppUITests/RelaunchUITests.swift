import XCTest

final class RelaunchUITests: ShopUITestCase {
    /// Two app processes in one test: the receipt runs in the first, the discount in the second.
    func testDiscountAfterRelaunch() {
        app.buttons["Add Coffee"].tap()
        app.buttons["Show receipt"].tap()
        XCTAssertTrue(app.staticTexts["receipt"].waitForExistence(timeout: 10))
        relaunch()
        app.buttons["Apply 10% off"].tap()
        XCTAssertEqual(app.staticTexts["total"].label, "Total: $0.00")
    }
}
