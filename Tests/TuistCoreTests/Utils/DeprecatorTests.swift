import Foundation
import XCTest

@testable import TuistCore
@testable import TuistCoreTesting

final class DeprecatorTests: XCTestCase {
    var context: MockContext!
    var subject: Deprecator!

    override func setUp() {
        super.setUp()
        context = Context.mockSharedContext()

        subject = Deprecator()
    }

    func test_notify() {
        subject.notify(deprecation: "foo", suggestion: "bar")
        XCTAssertPrinterOutputContains(context, expected: "foo will be deprecated in the next major release. Use bar instead.")
    }
}
