import Catalog
import XCTest

final class CatalogLoadingTests: XCTestCase {
    static var catalog: Catalog!

    override class func setUp() {
        super.setUp()
        catalog = try? Catalog.bundled()
    }

    func testBundledProductCount() {
        XCTAssertEqual(Self.catalog.products.count, 3)
    }

    func testLookupBySKU() {
        XCTAssertEqual(Self.catalog.product(for: "tea")?.name, "Tea")
    }
}
