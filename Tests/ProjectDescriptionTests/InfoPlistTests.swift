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
        let subject = InfoPlist.dictionary(["key": "value"])

        let expected =
            """
            {
               "type": "dictionary",
               "value": {
                 "key": "value"
               }
            }
            """
        assertCodableEqualToJson(subject, expected)
    }
}
