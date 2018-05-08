import Foundation
@testable import xcbuddykit
import XCTest

final class FatalErrorTests: XCTestCase {
    func test_description() {
        let error = NSError(domain: "test", code: 1, userInfo: nil)
        XCTAssertEqual(FatalError.abort(error).description, error.description)
        XCTAssertEqual(FatalError.bug(error).description, error.description)
        XCTAssertNil(FatalError.abortSilent(error).description)
        XCTAssertNil(FatalError.bugSilent(error).description)
    }

    func test_bug() {
        let error = NSError(domain: "test", code: 1, userInfo: nil)
        XCTAssertNil(FatalError.abort(error).bug)
        XCTAssertNil(FatalError.abortSilent(error).bug)
        XCTAssertEqual(FatalError.bug(error).bug as NSError?, error)
        XCTAssertEqual(FatalError.bugSilent(error).bug as NSError?, error)
    }
}
