import Foundation
import TSCBasic
import TuistCore
import TuistCoreTesting
import TuistGraph
import TuistGraphTesting
import TuistSupport
import XCTest
@testable import TuistGenerator
@testable import TuistSupportTesting

final class TargetScriptLinterTests: TuistUnitTestCase {
    var subject: TargetScriptLinter!

    override func setUp() {
        super.setUp()
        subject = TargetScriptLinter()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_lint_whenTheToolDoesntExist() {
        let action = TargetScript(
            name: "name",
            order: .pre,
            script: .tool(path: "randomtool")
        )
        let got = subject.lint(action)

        let expected = LintingIssue(
            reason: "The script tool 'randomtool' was not found in the environment",
            severity: .error
        )
        XCTAssertTrue(got.contains(expected))
    }

    func test_lint_whenPathDoesntExist() throws {
        let temporaryPath = try temporaryPath()
        let action = TargetScript(
            name: "name",
            order: .pre,
            script: .scriptPath(path: temporaryPath.appending(component: "invalid.sh"))
        )
        let got = subject.lint(action)

        let expected = LintingIssue(
            reason: "The script path \(action.path!.pathString) doesn't exist",
            severity: .error
        )
        XCTAssertTrue(got.contains(expected))
    }

    func test_lint_succeeds_when_embedded() throws {
        let action = TargetScript(
            name: "name",
            order: .pre,
            script: .embedded("echo 'Hello World'")
        )

        let got = subject.lint(action)
        let expected = [LintingIssue]()
        XCTAssertTrue(got.elementsEqual(expected))
    }

    func test_lint_warns_when_embedded_script_empty() {
        let action = TargetScript(
            name: "name",
            order: .pre,
            script: .embedded("")
        )

        let got = subject.lint(action)
        let expected = LintingIssue(reason: "The embedded script is empty", severity: .warning)
        XCTAssertTrue(got.contains(expected))
    }
}
