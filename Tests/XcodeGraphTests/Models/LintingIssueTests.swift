import Foundation
import Path
import TuistCore
import XCTest
@testable import TuistSupportTesting
@testable import XcodeGraph

final class LintingIssueTests: TuistUnitTestCase {
    func test_description() {
        let subject = LintingIssue(reason: "whatever", severity: .error)
        XCTAssertEqual(subject.description, "whatever")
    }

    func test_printAndThrowErrorsIfNeeded() throws {
        let first = LintingIssue(reason: "error", severity: .error)
        let second = LintingIssue(reason: "warning", severity: .warning)

        XCTAssertThrowsError(try [first, second].printAndThrowErrorsIfNeeded())

        XCTAssertPrinterOutputNotContains(
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

    func test_printAndThrowErrorsIfNeeded_whenErrorsOnly() throws {
        let first = LintingIssue(reason: "error", severity: .error)

        XCTAssertThrowsError(try [first].printAndThrowErrorsIfNeeded())

        XCTAssertPrinterErrorContains(
            """
            error
            """
        )
    }

    func test_printWarningsIfNeeded() throws {
        let first = LintingIssue(reason: "warning", severity: .warning)

        XCTAssertNoThrow([first].printWarningsIfNeeded())

        XCTAssertPrinterOutputContains(
            """
            warning
            """
        )
    }
}
