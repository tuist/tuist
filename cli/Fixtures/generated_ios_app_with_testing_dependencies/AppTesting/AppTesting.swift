import Testing
import XCTest

extension XCTestCase {
    public func XCTAssertCustom(file: StaticString = #file, line: UInt = #line) {
        XCTAssertTrue(true, file: file, line: line)
    }
}

public func customExpect(_ comment: @autoclosure () -> Comment? = nil, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(true, comment(), sourceLocation: sourceLocation)
}
