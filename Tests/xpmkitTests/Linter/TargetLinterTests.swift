import Basic
import Foundation
import XCTest
@testable import xpmkit

final class TargetLinterTests: XCTestCase {
    var subject: TargetLinter!

    override func setUp() {
        super.setUp()
        subject = TargetLinter()
    }

    func test_lint_when_target_no_source_files() {
        let buildPhase = SourcesBuildPhase(buildFiles: [])
        let buildPhases: [BuildPhase] = [buildPhase]
        let target = Target.test(buildPhases: buildPhases)
        let got = subject.lint(target: target)
        XCTAssertTrue(got.contains(LintingIssue(reason: "The target \(target.name) doesn't contain source files.", severity: .warning)))
    }

    func test_lint_when_more_than_one_sources_build_phase() {
        let buildPhase = SourcesBuildPhase(buildFiles: [])
        let buildPhases: [BuildPhase] = [buildPhase, buildPhase]
        let target = Target.test(buildPhases: buildPhases)

        let got = subject.lint(target: target)

        XCTAssertTrue(got.contains(LintingIssue(reason: "The target \(target.name) has more than one sources build phase.", severity: .error)))
    }

    func test_lint_when_more_than_one_resources_build_phase() {
        let buildPhase = ResourcesBuildPhase(buildFiles: [])
        let buildPhases: [BuildPhase] = [buildPhase, buildPhase]
        let target = Target.test(buildPhases: buildPhases)

        let got = subject.lint(target: target)

        XCTAssertTrue(got.contains(LintingIssue(reason: "The target \(target.name) has more than one resources build phase.", severity: .error)))
    }

    func test_lint_when_more_than_one_headers_build_phase() {
        let buildPhase = HeadersBuildPhase(buildFiles: [])
        let buildPhases: [BuildPhase] = [buildPhase, buildPhase]
        let target = Target.test(buildPhases: buildPhases)

        let got = subject.lint(target: target)

        XCTAssertTrue(got.contains(LintingIssue(reason: "The target \(target.name) has more than one headers build phase.", severity: .error)))
    }

    func test_lint_when_a_infoplist_file_is_being_copied() {
        let path = AbsolutePath("/Info.plist")
        let buildPhase = ResourcesBuildPhase(buildFiles: [ResourcesBuildFile([path])])
        let target = Target.test(buildPhases: [buildPhase])

        let got = subject.lint(target: target)

        XCTAssertTrue(got.contains(LintingIssue(reason: "Info.plist at path \(path.asString) being copied into the target \(target.name) product.", severity: .warning)))
    }

    func test_lint_when_a_entitlements_file_is_being_copied() {
        let path = AbsolutePath("/App.entitlements")
        let buildPhase = ResourcesBuildPhase(buildFiles: [ResourcesBuildFile([path])])
        let target = Target.test(buildPhases: [buildPhase])

        let got = subject.lint(target: target)

        XCTAssertTrue(got.contains(LintingIssue(reason: "Entitlements file at path \(path.asString) being copied into the target \(target.name) product.", severity: .warning)))
    }
}
