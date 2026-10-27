@testable import Feature
import Library
import XCTest

final class FeatureTests: XCTestCase {
    func testHello() {
        Feature.hello()
        _ = Library.hello()
    }
}
