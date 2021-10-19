import Foundation
import XCTest

@testable import TuistSupport
@testable import TuistSupportTesting

final class DeprecatorTests: TuistUnitTestCase {
    var subject: Deprecator!

    override func setUp() {
        super.setUp()
        subject = Deprecator()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_notify() {
        subject.notify(deprecation: "foo", suggestion: "Use bar")
        XCTAssertPrinterOutputContains("foo will be deprecated in the next major release. Use bar instead.")
    }
}
