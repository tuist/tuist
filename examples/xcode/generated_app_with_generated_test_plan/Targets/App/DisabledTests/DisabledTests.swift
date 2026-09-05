import XCTest

final class DisabledTests: XCTestCase {
    func test_disabled() {
        XCTFail("The generated test plan must disable this target")
    }
}
