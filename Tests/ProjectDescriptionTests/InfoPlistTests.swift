import Foundation
import TuistCoreTesting
import XCTest

@testable import ProjectDescription

final class InfoPlistTests: XCTestCase {
    func test_toJSON() throws {
        let subject = InfoPlist.file(path: "path/Info.plist")

        let expected =
            """
            {
               "type": "file",
               "path": "path/Info.plist"
            }
            """

        XCTAssertCodableEqualToJson(subject, expected)
    }
}
