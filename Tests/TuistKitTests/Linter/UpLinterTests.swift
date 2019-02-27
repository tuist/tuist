import Basic
import Foundation
import XCTest
@testable import TuistKit

final class UpLinterTests: XCTestCase {
    var subject: UpLinter!

    override func setUp() {
        super.setUp()
        subject = UpLinter()
    }

    func test_lint_when_a_custom_up_has_an_empty_meet() {
        let up = UpCustom(name: "test", meet: [], isMet: ["which", "tool"])
        let got = subject.lint(up: up)

        XCTAssertTrue(got.contains(LintingIssue(reason: "The up task 'test' meet command is empty", severity: .error)))
    }

    func test_lint_when_a_custom_up_has_an_empty_isMet() {
        let up = UpCustom(name: "test", meet: ["./install.sh"], isMet: [])
        let got = subject.lint(up: up)

        XCTAssertTrue(got.contains(LintingIssue(reason: "The up task 'test' isMet command is empty", severity: .error)))
    }
}
