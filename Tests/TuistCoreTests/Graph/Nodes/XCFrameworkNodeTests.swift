import Basic
import Foundation
import XCTest

@testable import TuistCore
@testable import TuistSupportTesting

final class XCFrameworkNodeTests: TuistUnitTestCase {
    var subject: XCFrameworkNode!

    override func setUp() {
        super.setUp()
        subject = XCFrameworkNode.test()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_name() {
        XCTAssertEqual(subject.name, "MyFramework")
    }

    func test_encode() {
        // Given

        let expected = """
        {
          "path" : "/MyFramework/MyFramework.xcframework",
          "name" : "MyFramework",
          "type" : "xcframework",
          "linking": "dynamic",
          "info_plist" : {
            "AvailableLibraries" : [
              {
                "SupportedArchitectures" : [
                  "i386"
                ],
                "LibraryIdentifier" : "test",
                "LibraryPath" : "relative/to/library"
              }
            ]
          }
        }
        """

        // Then
        XCTAssertEncodableEqualToJson(subject, expected)
    }
}
