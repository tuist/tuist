import Foundation
import TSCBasic
import TuistCore
import TuistSupportTesting
import XCTest

extension TuistTestCase {
    // MARK: - XCTAssertions

    /// Fails the test if the list of linting issues doesn't contain the given linting issue.
    /// - Parameters:
    ///   - issues: List of issues in which the issue will be checked.
    ///   - issue: Issue to be checked in the list. If it doesn't exist, the test will fail.
    public func XCTContainsLintingIssue(
        _ issues: [LintingIssue],
        _ issue: LintingIssue,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        if !issues.contains(issue) {
            XCTFail("The list doesn't contain the issue '\(issue)' and it should", file: file, line: line)
        }
    }

    /// Fails the test if the list of linting issues doesn't contain the given linting issue.
    /// - Parameters:
    ///   - issues: List of issues in which the issue will be checked.
    ///   - issue: Issue to be checked in the list. If it doesn't exist, the test will fail.
    public func XCTDoesNotContainLintingIssue(
        _ issues: [LintingIssue],
        _ issue: LintingIssue,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        if issues.contains(issue) {
            XCTFail("The list contains the issue '\(issue)' and it shouldn't", file: file, line: line)
        }
    }
}
