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
          "path" : "\\/MyFramework.xcframework",
          "libraries" : [
            {
              "SupportedArchitectures" : [
                "x86_64"
              ],
              "LibraryIdentifier" : "ios-x86_64-simulator",
              "LibraryPath" : "MyFramework.framework"
            },
            {
              "SupportedArchitectures" : [
                "arm64"
              ],
              "LibraryIdentifier" : "ios-arm64",
              "LibraryPath" : "MyFramework.framework"
            }
          ],
          "name" : "MyFramework",
          "type" : "precompiled"
        }

        """

        // Then
        XCTAssertEncodableEqualToJson(subject, expected)
    }
}
