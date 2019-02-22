import Basic
import Foundation
import XCTest
@testable import TuistCoreTesting
@testable import TuistKit

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

        XCTAssertEqual(printer.printWithColorArgs.first?.0, "The following issues have been found:")
        XCTAssertEqual(printer.printWithColorArgs.first?.1, .yellow)
        XCTAssertEqual(printer.printArgs.first, "  - warning")

        XCTAssertEqual(printer.printWithColorArgs.last?.0, "\nThe following critical issues have been found:")
        XCTAssertEqual(printer.printWithColorArgs.last?.1, .red)
        XCTAssertEqual(printer.printArgs.last, "  - error")
    }

    func test_printAndThrowIfNeeded_whenErrorsOnly() throws {
        let printer = MockPrinter()
        let first = LintingIssue(reason: "error", severity: .error)

        XCTAssertThrowsError(try [first].printAndThrowIfNeeded(printer: printer))

        XCTAssertEqual(printer.printWithColorArgs.last?.0, "The following critical issues have been found:")
        XCTAssertEqual(printer.printWithColorArgs.last?.1, .red)
        XCTAssertEqual(printer.printArgs.last, "  - error")
    }
}
