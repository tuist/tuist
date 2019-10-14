import Basic
import Foundation
import TuistCore
import XCTest
@testable import TuistCoreTesting
@testable import TuistGenerator

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
                                  tool: "randomtool")
        let got = subject.lint(action)

        let expected = LintingIssue(reason: "The action tool 'randomtool' was not found in the environment",
                                    severity: .error)
        XCTAssertTrue(got.contains(expected))
    }

    func test_lint_whenPathDoesntExist() throws {
        let temporaryPath = try self.temporaryPath()
        let action = TargetAction(name: "name",
                                  order: .pre,
                                  path: temporaryPath.appending(component: "invalid.sh"))
        let got = subject.lint(action)

        let expected = LintingIssue(reason: "The action path \(action.path!.pathString) doesn't exist",
                                    severity: .error)
        XCTAssertTrue(got.contains(expected))
    }
}
