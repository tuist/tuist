import XCTest
@testable import PackageA

final class PackageAClassTests: XCTestCase {
    func testExample() {
        XCTAssertEqual(PackageAClass().text, "PackageAClass")
    }

    static var allTests = [
        ("testExample", testExample),
    ]
}
