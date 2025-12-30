import Foundation
import TuistSupportTesting
import XCTest

@testable import ProjectDescription

final class InfoPlistTests: XCTestCase {
    func test_toJSON_when_file() throws {
        let subject = InfoPlist.file(path: "path/Info.plist")
        XCTAssertCodable(subject)
    }

    func test_toJSON_when_dictionary() throws {
        let subject = InfoPlist.dictionary([
            "string": "string",
            "number": 1,
            "boolean": true,
            "dictionary": ["a": "b"],
            "array": ["a", "b"],
            "real": 0.8,
        ])
        XCTAssertCodable(subject)
    }
}
