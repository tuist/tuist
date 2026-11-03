import XCTest

final class ShopUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testShowsCatalog() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["Coffee"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Total: $0.00"].exists)
    }

    func testApplyingDiscountUpdatesTotal() {
        let app = XCUIApplication()
        app.launch()
        app.buttons["Add Coffee"].tap()
        app.buttons["Apply 10% off"].tap()
        XCTAssertEqual(app.staticTexts["total"].label, "Total: $3.15")
    }
}
