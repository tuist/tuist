import Path
import TuistCore
import XcodeGraph
import XCTest
@testable import TuistHasher

class PlistrExtrasTests: XCTestCase {
    func test_normalize() throws {
        XCTAssertEqual(Plist.Value.string("test").normalize() as? String, "test")
        XCTAssertEqual(Plist.Value.integer(1).normalize() as? Int, 1)
        XCTAssertEqual(Plist.Value.real(1).normalize() as? Double, 1)
        XCTAssertEqual(Plist.Value.boolean(true).normalize() as? Bool, true)
        XCTAssertEqual(Plist.Value.array([.string("test")]).normalize() as? [String], ["test"])
        XCTAssertEqual(Plist.Value.dictionary(["test": .string("tuist")]).normalize() as? [String: String], ["test": "tuist"])
    }
}
