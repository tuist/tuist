import Foundation
import TSCBasic
import TuistCore
import XCTest
@testable import TuistGraph
@testable import TuistSupportTesting

final class LintingIssueTests: TuistUnitTestCase {
    func test_description() {
        let subject = LintingIssue(reason: "whatever", severity: .error)
        XCTAssertEqual(subject.description, "whatever")
    }

    func test_printAndThrowIfNeeded() throws {
        let first = LintingIssue(reason: "error", severity: .error)
        let second = LintingIssue(reason: "warning", severity: .warning)

        XCTAssertThrowsError(try [first, second].printAndThrowIfNeeded())

        XCTAssertPrinterOutputContains(
            """
            warning
            """
        )
        XCTAssertPrinterErrorContains(
            """
            error
            """
        )
    }

    func test_printAndThrowIfNeeded_whenErrorsOnly() throws {
        let first = LintingIssue(reason: "error", severity: .error)

        XCTAssertThrowsError(try [first].printAndThrowIfNeeded())

        XCTAssertPrinterErrorContains(
            """
            error
            """
        )
    }
}
