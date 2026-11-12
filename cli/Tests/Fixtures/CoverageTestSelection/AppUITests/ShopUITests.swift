import XCTest

final class ShopUITests: ShopUITestCase {
    func testShowsCatalog() {
        XCTAssertTrue(app.staticTexts["Coffee"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Total: $0.00"].exists)
    }

    func testApplyingDiscountUpdatesTotal() {
        app.buttons["Add Coffee"].tap()
        app.buttons["Apply 10% off"].tap()
        XCTAssertEqual(app.staticTexts["total"].label, "Total: $3.15")
    }
}
