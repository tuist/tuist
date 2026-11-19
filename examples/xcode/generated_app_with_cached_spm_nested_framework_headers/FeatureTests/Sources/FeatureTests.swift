import Feature
import XCTest

final class FeatureTests: XCTestCase {
    func testValue() {
        XCTAssertEqual(featureValue(), 42)
    }
}
