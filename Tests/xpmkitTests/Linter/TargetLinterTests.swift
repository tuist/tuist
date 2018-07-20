import Foundation
import XCTest
@testable import xpmkit

final class TargetLinterTests: XCTestCase {
    var subject: TargetLinter!

    override func setUp() {
        super.setUp()
        subject = TargetLinter()
    }

    func test_validate_throws_when_target_no_source_files() throws {
        let buildPhase = SourcesBuildPhase(buildFiles: [])
        let buildPhases: [BuildPhase] = [buildPhase]
        let target = Target.test(buildPhases: buildPhases)
        let got = subject.lint(target: target)
        XCTAssertTrue(got.contains(LintingIssue(reason: "The target \(target.name) doesn't contain source files.", severity: .warning)))
    }
}
