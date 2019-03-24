import Basic
import Foundation
import XCTest
import TuistCore
@testable import TuistGenerator

final class ProjectLinterTests: XCTestCase {
    var subject: ProjectLinter!

    override func setUp() {
        super.setUp()
        subject = ProjectLinter()
    }

    func test_validate_when_there_are_duplicated_targets() throws {
        let target = Target.test(name: "A")
        let project = Project.test(targets: [target, target])
        let got = subject.lint(project)
        XCTAssertTrue(got.contains(LintingIssue(reason: "Targets A from project at \(project.path.asString) have duplicates.", severity: .error)))
    }
}
