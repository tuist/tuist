import XCTest

var tests = [XCTestCaseEntry]()

XCTMain(tests)

// All tests that are testing Arena package are added here so that we can test them collectively
final class AllTests: XCTestCase {
    func testAllTargetsTests() {
        tests.values.forEach { value() }
    }
}
