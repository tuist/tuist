import Basic
import Foundation
@testable import TuistCoreTesting
@testable import TuistKit
import XCTest

final class TargetLinterTests: XCTestCase {
    var subject: TargetLinter!
    var fileHandler: MockFileHandler!

    override func setUp() {
        super.setUp()
        fileHandler = try! MockFileHandler()
        subject = TargetLinter(fileHandler: fileHandler)
    }

    func test_lint_when_target_no_source_files() {
        let target = Target.test(sources: [])
        let got = subject.lint(target: target)
        XCTAssertTrue(got.contains(LintingIssue(reason: "The target \(target.name) doesn't contain source files.", severity: .warning)))
    }

    func test_lint_when_a_infoplist_file_is_being_copied() {
        let path = AbsolutePath("/Info.plist")
        let target = Target.test(resources: [path])

        let got = subject.lint(target: target)

        XCTAssertTrue(got.contains(LintingIssue(reason: "Info.plist at path \(path.asString) being copied into the target \(target.name) product.", severity: .warning)))
    }

    func test_lint_when_a_entitlements_file_is_being_copied() {
        let path = AbsolutePath("/App.entitlements")
        let target = Target.test(resources: [path])

        let got = subject.lint(target: target)

        XCTAssertTrue(got.contains(LintingIssue(reason: "Entitlements file at path \(path.asString) being copied into the target \(target.name) product.", severity: .warning)))
    }

    func test_lint_when_entitlements_not_missing() {
        let path = fileHandler.currentPath.appending(component: "Info.plist")
        let target = Target.test(infoPlist: path)

        let got = subject.lint(target: target)

        XCTAssertTrue(got.contains(LintingIssue(reason: "Info.plist file not found at path \(path.asString)", severity: .error)))
    }

    func test_lint_when_infoplist_not_found() {
        let path = fileHandler.currentPath.appending(component: "App.entitlements")
        let target = Target.test(entitlements: path)

        let got = subject.lint(target: target)

        XCTAssertTrue(got.contains(LintingIssue(reason: "Entitlements file not found at path \(path.asString)", severity: .error)))
    }
}
