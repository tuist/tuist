import XCTest
@testable import MacOSStaticFramework

final class MacOSStaticFrameworkClassTests: XCTestCase {
    func test_resourceURL() {
        XCTAssertNotNil(MacOSStaticFrameworkClass().logoURL)
    }
}
