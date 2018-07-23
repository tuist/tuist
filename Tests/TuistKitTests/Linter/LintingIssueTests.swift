import Foundation
@testable import TuistCoreTesting
@testable import TuistKit
import XCTest

final class LintingErrorTests: XCTestCase {
    var subject: LintingError!

    override func setUp() {
        super.setUp()
        subject = LintingError(issues: [LintingIssue(reason: "test", severity: .error)])
    }

    func test_type() {
        XCTAssertEqual(subject.type, .abort)
    }

    func test_equal() {
        XCTAssertEqual(subject, subject)
    }

    func test_description() {
        XCTAssertEqual(subject.description, "- test")
    }
}

final class LintingIssueTests: XCTestCase {
    func test_description() {
        let subject = LintingIssue(reason: "whatever", severity: .error)
        XCTAssertEqual(subject.description, "whatever")
    }

    func test_equatable() {
        let first = LintingIssue(reason: "whatever", severity: .error)
        let second = LintingIssue(reason: "whatever", severity: .error)
        let third = LintingIssue(reason: "whatever", severity: .warning)
        XCTAssertEqual(first, second)
        XCTAssertNotEqual(first, third)
    }

    func test_printAndThrowIfNeeded() throws {
        let printer = MockPrinter()
        let first = LintingIssue(reason: "error", severity: .error)
        let second = LintingIssue(reason: "warning", severity: .warning)

        XCTAssertThrowsError(try [first, second].printAndThrowIfNeeded(printer: printer))

        XCTAssertEqual(printer.printWarningArgs, ["The following issues have been found:\n- warning"])
        XCTAssertEqual(printer.printErrorMessageArgs, ["The following critical issues have been found:\n- error"])
    }
}
