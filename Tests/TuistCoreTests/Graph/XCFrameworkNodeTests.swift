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
          "libraries" : [
            {
              "SupportedArchitectures" : [
                "i386"
              ],
              "LibraryIdentifier" : "test",
              "LibraryPath" : "relative/to/library"
            },
          ],
          "name" : "MyFramework",
          "type" : "precompiled"
        }

        """

        // Then
        XCTAssertEncodableEqualToJson(subject, expected)
    }
}
