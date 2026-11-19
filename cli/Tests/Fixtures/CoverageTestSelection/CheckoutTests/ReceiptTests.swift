import Catalog
import XCTest
@testable import App

final class ReceiptTests: XCTestCase {
    func testListsItems() {
        let lines = Receipt.lines(for: [Product(sku: "tea", name: "Tea", priceCents: 300)], discountPercent: 0)
        XCTAssertEqual(lines, ["Tea $3.00"])
    }

    func testAppliesDiscount() {
        let lines = Receipt.lines(for: [Product(sku: "tea", name: "Tea", priceCents: 300)], discountPercent: 10)
        XCTAssertEqual(lines, ["Tea $3.00", "10% off: $2.70"])
    }
}
