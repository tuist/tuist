import Foundation
@testable import xcbuddykit
import XCTest

fileprivate struct TestError: Error, ErrorStringConvertible {
    var errorDescription: String { return "" }
}

final class FatalErrorTests: XCTestCase {
    func test_description() {
        let error = TestError()
        XCTAssertEqual(FatalError.abort(error).errorDescription, error.errorDescription)
        XCTAssertEqual(FatalError.bug(error).errorDescription, error.errorDescription)
        XCTAssertTrue(FatalError.abortSilent(error).errorDescription.isEmpty)
        XCTAssertTrue(FatalError.bugSilent(error).errorDescription.isEmpty)
    }

    func test_bug() {
        let error = TestError()
        XCTAssertNil(FatalError.abort(error).bug)
        XCTAssertNil(FatalError.abortSilent(error).bug)
        XCTAssertEqual(FatalError.bug(error).bug as NSError?, error as NSError)
        XCTAssertEqual(FatalError.bugSilent(error).bug as NSError?, error as NSError)
    }
}
