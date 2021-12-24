import Foundation
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport
import XCTest
@testable import TuistGenerator
@testable import TuistGraphTesting
@testable import TuistSupportTesting

final class SettingsLinterTests: TuistUnitTestCase {
    var subject: SettingsLinter!

    override func setUp() {
        super.setUp()
        subject = SettingsLinter()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_lint_project_when_config_files_are_missing() throws {
        // Given
        let temporaryPath = try temporaryPath()
        let debugPath = temporaryPath.appending(component: "Debug.xcconfig")
        let releasePath = temporaryPath.appending(component: "Release.xcconfig")
        let settings = Settings(configurations: [
            .debug: Configuration(xcconfig: debugPath),
            .release: Configuration(xcconfig: releasePath),
        ])
        let project = Project.test(settings: settings)

        // When
        let got = subject.lint(project: project)

        // Then
        XCTAssertEqual(
            got,
            [
                LintingIssue(reason: "Configuration file not found at path \(debugPath.pathString)", severity: .error),
                LintingIssue(
                    reason: "Configuration file not found at path \(releasePath.pathString)",
                    severity: .error
                ),
            ]
        )
    }

    func test_lint_target_when_config_files_are_missing() throws {
        // Given
        let temporaryPath = try temporaryPath()
        let debugPath = temporaryPath.appending(component: "Debug.xcconfig")
        let releasePath = temporaryPath.appending(component: "Release.xcconfig")
        let settings = Settings(configurations: [
            .debug: Configuration(xcconfig: debugPath),
            .release: Configuration(xcconfig: releasePath),
        ])
        let target = Target.test(settings: settings)

        // When
        let got = subject.lint(target: target)

        // Then
        XCTAssertEqual(
            got,
            [
                LintingIssue(reason: "Configuration file not found at path \(debugPath.pathString)", severity: .error),
                LintingIssue(
                    reason: "Configuration file not found at path \(releasePath.pathString)",
                    severity: .error
                ),
            ]
        )
    }

    func test_lint_project_when_no_configurations() {
        // Given
        let settings = Settings(base: ["A": "B"], configurations: [:])
        let project = Project.test(settings: settings)

        // When
        let got = subject.lint(project: project)

        // Then
        XCTAssertEqual(got, [LintingIssue(reason: "The project at path /Project has no configurations", severity: .error)])
    }

    func test_lint_target_when_no_configurations() {
        // Given
        let settings = Settings(base: ["A": "B"], configurations: [:])
        let target = Target.test(settings: settings)

        // When
        let got = subject.lint(target: target)

        // Then
        XCTAssertEqual(got, [])
    }

    func test_lint_project_when_platform_and_deployment_target_are_compatible() {
        // Given
        let target = Target.test(platform: .macOS, deploymentTarget: .macOS("10.14.5"))

        // When
        let got = subject.lint(target: target)

        // Then
        XCTAssertEqual(got, [])
    }

    func test_lint_project_when_platform_and_deployment_target_are_not_compatible() {
        // Given
        let target = Target.test(platform: .iOS, deploymentTarget: .macOS("10.14.5"))

        // When
        let got = subject.lint(target: target)

        // Then
        XCTAssertEqual(
            got,
            [LintingIssue(
                reason: "Found an inconsistency between a platform `iOS` and deployment target `macOS`",
                severity: .error
            )]
        )
    }
}
