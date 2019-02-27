import Basic
import Foundation
import TuistCore
import XCTest
@testable import TuistCoreTesting
@testable import TuistKit

final class TargetActionLinterTests: XCTestCase {
    var system: System!
    var fileHandler: MockFileHandler!
    var subject: TargetActionLinter!

    override func setUp() {
        super.setUp()
        system = System()
        fileHandler = try! MockFileHandler()
        subject = TargetActionLinter(system: system,
                                     fileHandler: fileHandler)
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

    func test_lint_whenPathDoesntExist() {
        let action = TargetAction(name: "name",
                                  order: .pre,
                                  path: fileHandler.currentPath.appending(component: "invalid.sh"))
        let got = subject.lint(action)

        let expected = LintingIssue(reason: "The action path \(action.path!.asString) doesn't exist",
                                    severity: .error)
        XCTAssertTrue(got.contains(expected))
    }
}
