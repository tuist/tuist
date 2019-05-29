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
        let dictionary = ["key": "value"]
        let data = try JSONSerialization.data(withJSONObject: dictionary,
                                              options: [])
        let subject = InfoPlist.dictionary(dictionary)

        let expected =
            """
            {
               "type": "dictionary",
               "value": "\(data.base64EncodedString())"
            }
            """
        assertCodableEqualToJson(subject, expected)
    }
}
