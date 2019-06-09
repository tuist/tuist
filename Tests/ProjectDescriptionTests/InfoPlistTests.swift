import Foundation
import TuistCoreTesting
import XCTest

@testable import ProjectDescription

final class InfoPlistTests: XCTestCase {
    func test_toJSON_when_file() throws {
        let subject = InfoPlist.file(path: "path/Info.plist")

        let expected =
            """
            {
               "type": "file",
               "value": "path/Info.plist"
            }
            """

        XCTAssertCodableEqualToJson(subject, expected)
    }

    func test_toJSON_when_dictionary() throws {
        let subject = InfoPlist.dictionary([
            "string": "string",
            "number": 1,
            "boolean": true,
            "dictionary": ["a": "b"],
            "array": ["a", "b"]
        ])

        let expected =
            """
            {
                "type": "dictionary",
                "value": {
                    "string": "string",
                    "number": "1",
                    "boolean": "true",
                    "dictionary": {
                        "a": "b"
                    },
                    "array": ["a", "b"]
                }
            }
            """
        assertCodableEqualToJson(subject, expected)
    }
}
