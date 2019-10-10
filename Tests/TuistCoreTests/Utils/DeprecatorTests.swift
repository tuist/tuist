import Foundation
import XCTest

@testable import TuistCore
@testable import TuistCoreTesting

final class DeprecatorTests: TuistUnitTestCase {
    var subject: Deprecator!

    override func setUp() {
        super.setUp()
        subject = Deprecator()
    }

    override func tearDown() {
        super.tearDown()
        subject = nil
    }

    func test_notify() {
        subject.notify(deprecation: "foo", suggestion: "bar")
        XCTAssertPrinterOutputContains("foo will be deprecated in the next major release. Use bar instead.")
    }
}
