import Foundation
import XCTest

@testable import TuistCore
@testable import TuistCoreTesting

final class DeprecatorTests: XCTestCase {
    var printer: MockPrinter!
    var subject: Deprecator!

    override func setUp() {
        super.setUp()
        printer = MockPrinter()
        subject = Deprecator(printer: printer)
    }

    func test_notify() {
        subject.notify(deprecation: "foo", suggestion: "bar")
        XCTAssertEqual(printer.printDeprecationArgs, ["foo will be deprecated in the next major release. Use bar instead."])
    }
}
