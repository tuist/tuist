import Foundation
import TSCBasic
import TuistCore
import TuistCoreTesting
import TuistSupport
import XCTest
import TuistGraph
import TuistGraphTesting
@testable import TuistGenerator
@testable import TuistSupportTesting

final class TargetActionLinterTests: TuistUnitTestCase {
    var subject: TargetActionLinter!

    override func setUp() {
        super.setUp()
        subject = TargetActionLinter()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_lint_whenTheToolDoesntExist() {
        let action = TargetAction(name: "name",
                                  order: .pre,
                                  script: .tool("randomtool"))
        let got = subject.lint(action)

        let expected = LintingIssue(reason: "The action tool 'randomtool' was not found in the environment",
                                    severity: .error)
        XCTAssertTrue(got.contains(expected))
    }

    func test_lint_whenPathDoesntExist() throws {
        let temporaryPath = try self.temporaryPath()
        let action = TargetAction(name: "name",
                                  order: .pre,
                                  script: .scriptPath(temporaryPath.appending(component: "invalid.sh")))
        let got = subject.lint(action)

        let expected = LintingIssue(reason: "The action path \(action.path!.pathString) doesn't exist",
                                    severity: .error)
        XCTAssertTrue(got.contains(expected))
    }

    func test_lint_succeeds_when_embedded() throws {
        let action = TargetAction(name: "name",
                                  order: .pre,
                                  script: .embedded("echo 'Hello World'"))

        let got = subject.lint(action)
        let expected = [LintingIssue]()
        XCTAssertTrue(got.elementsEqual(expected))
    }

    func test_lint_warns_when_embedded_script_empty() {
        let action = TargetAction(name: "name",
                                  order: .pre,
                                  script: .embedded(""))

        let got = subject.lint(action)
        let expected = LintingIssue(reason: "The embedded script is empty", severity: .warning)
        XCTAssertTrue(got.contains(expected))
    }
}
