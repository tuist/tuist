import XCTest
@testable import MultiPlatformTransitiveDynamicFramework

final class MultiPlatformTransitiveDynamicFrameworkClassTests: XCTestCase {
    func test_print() {
        let instance = MultiPlatformTransitiveDynamicFrameworkClass()
        XCTAssertNotNil(instance)
    }
}
