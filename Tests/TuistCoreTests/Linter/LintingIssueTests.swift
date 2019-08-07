import Basic
import Foundation
import XCTest
@testable import TuistCore
@testable import TuistCoreTesting

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

        XCTAssertTrue(printer.standardOutput.contains("""
        The following issues have been found:
          - warning
        """))
        XCTAssertTrue(printer.standardError.contains("""
        The following critical issues have been found:
          - error
        """))
    }

    func test_printAndThrowIfNeeded_whenErrorsOnly() throws {
        let printer = MockPrinter()
        let first = LintingIssue(reason: "error", severity: .error)

        XCTAssertThrowsError(try [first].printAndThrowIfNeeded(printer: printer))

        XCTAssertTrue(printer.standardError.contains("""
        The following critical issues have been found:
          - error
        """))
    }
}
