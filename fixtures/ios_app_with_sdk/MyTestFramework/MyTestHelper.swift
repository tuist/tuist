import XCTest

public class MyTestHelper {
    public init() {

    }

    public func customAssert(_ value: Bool, file: StaticString = #file, line: Int = #line) {
        XCTAssertTrue(value, file: file, line: line)
    }
}
