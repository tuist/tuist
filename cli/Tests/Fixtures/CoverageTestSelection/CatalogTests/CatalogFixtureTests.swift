import Catalog
import Foundation
import XCTest

final class CatalogFixtureTests: XCTestCase {
    func testFixtureParses() throws {
        // Fixtures/catalog-fixture.json is read at runtime and belongs to no target.
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/catalog-fixture.json")
        let catalog = try Catalog(jsonData: Data(contentsOf: url))
        XCTAssertEqual(catalog.products.map(\.sku), ["bagel"])
    }
}
