import XCTest

/// One app process for the whole class, launched outside any test.
final class SharedAppUITests: XCTestCase {
    static var app: XCUIApplication!

    override class func setUp() {
        super.setUp()
        app = XCUIApplication()
        app.launch()
    }

    override class func tearDown() {
        app.terminate()
        super.tearDown()
    }

    func testShowsTotal() {
        XCTAssertTrue(Self.app.staticTexts["total"].waitForExistence(timeout: 10))
    }

    func testShowsReceipt() {
        Self.app.buttons["Show receipt"].tap()
        XCTAssertTrue(Self.app.staticTexts["receipt"].waitForExistence(timeout: 10))
    }
}
