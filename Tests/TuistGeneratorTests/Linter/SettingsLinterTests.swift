import Foundation
import TuistCore
import TuistSupport
import XcodeGraph
import XCTest
@testable import TuistGenerator
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

    func test_lint_project_when_config_files_are_missing() async throws {
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
        let got = try await subject.lint(project: project)

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

    func test_lint_target_when_config_files_are_missing() async throws {
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
        let got = try await subject.lint(target: target)

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

    func test_lint_project_when_no_configurations() async throws {
        // Given
        let settings = Settings(base: ["A": "B"], configurations: [:])
        let project = Project.test(settings: settings)

        // When
        let got = try await subject.lint(project: project)

        // Then
        XCTAssertEqual(got, [LintingIssue(reason: "The project at path /Project has no configurations", severity: .error)])
    }

    func test_lint_target_when_no_configurations() async throws {
        // Given
        let settings = Settings(base: ["A": "B"], configurations: [:])
        let target = Target.test(settings: settings)

        // When
        let got = try await subject.lint(target: target)

        // Then
        XCTAssertEqual(got, [])
    }

    func test_lint_project_when_platform_and_deployment_target_are_compatible() async throws {
        // Given
        let target = Target.test(platform: .macOS, deploymentTarget: .macOS("10.14.5"))

        // When
        let got = try await subject.lint(target: target)

        // Then
        XCTAssertEqual(got, [])
    }

    func test_lint_project_when_platform_and_deployment_target_are_not_compatible() async throws {
        // Given
        let target = Target.test(platform: .iOS, deploymentTarget: .macOS("10.14.5"))

        // When
        let got = try await subject.lint(target: target)

        // Then
        XCTAssertEqual(
            got,
            [LintingIssue(
                reason: "Found deployment platforms (macOS) missing corresponding destination",
                severity: .error
            )]
        )
    }

    func test_lint_project_when_default_config_name_is_valid() async throws {
        // Given
        let settings = Settings(
            configurations: [
                .debug("Debug Development"): Configuration(),
                .release("Release Development"): Configuration(),
                .debug("Debug Production"): Configuration(),
                .release("Release Production"): Configuration(),
            ],
            defaultConfiguration: "Debug Development"
        )
        let project = Project.test(settings: settings)

        // When
        let got = try await subject.lint(project: project)

        // Then
        XCTAssertEqual(got, [])
    }

    func test_lint_project_when_default_config_name_is_not_valid() async throws {
        // Given
        let settings = Settings(
            configurations: [
                .debug("Debug Development"): Configuration(),
                .release("Release Development"): Configuration(),
                .debug("Debug Production"): Configuration(),
                .release("Release Production"): Configuration(),
            ],
            defaultConfiguration: "Wrong Config Name"
        )
        let project = Project.test(settings: settings)

        // When
        let got = try await subject.lint(project: project)

        // Then
        XCTAssertEqual(
            got,
            [LintingIssue(
                reason: "The project '\(project.name)' specifies a default configuration '\(settings.defaultConfiguration ?? "")', which is not included in its available configurations: \(settings.configurations.keys.map(\.name).joined(separator: ", "))",
                severity: .error
            )]
        )
    }

    func test_lint_target_when_no_default_config_name_provided() async throws {
        // Given
        let settings = Settings(
            configurations: [
                .debug("Debug Development"): Configuration(),
                .release("Release Development"): Configuration(),
                .debug("Debug Production"): Configuration(),
                .release("Release Production"): Configuration(),
            ]
        )
        let target = Target.test(settings: settings)

        // When
        let got = try await subject.lint(target: target)

        // Then
        XCTAssertEqual(got, [])
    }

    func test_lint_target_when_default_config_name_is_valid() async throws {
        // Given
        let settings = Settings(
            configurations: [
                .debug("Debug Development"): Configuration(),
                .release("Release Development"): Configuration(),
                .debug("Debug Production"): Configuration(),
                .release("Release Production"): Configuration(),
            ],
            defaultConfiguration: "Debug Development"
        )
        let target = Target.test(settings: settings)

        // When
        let got = try await subject.lint(target: target)

        // Then
        XCTAssertEqual(
            got,
            [LintingIssue(
                reason: "The default configuration '\(settings.defaultConfiguration ?? "")' for target '\(target.name)' will be overridden by the project’s default configuration.",
                severity: .warning
            )]
        )
    }

    func test_lint_target_when_default_config_name_is_not_valid() async throws {
        // Given
        let settings = Settings(
            configurations: [
                .debug("Debug Development"): Configuration(),
                .release("Release Development"): Configuration(),
                .debug("Debug Production"): Configuration(),
                .release("Release Production"): Configuration(),
            ],
            defaultConfiguration: "Wrong Config Name"
        )
        let target = Target.test(settings: settings)

        // When
        let got = try await subject.lint(target: target)

        // Then
        XCTAssertEqual(
            got,
            [
                LintingIssue(
                    reason: "The target '\(target.name)' specifies a default configuration '\(settings.defaultConfiguration ?? "")', which is not included in its available configurations: \(settings.configurations.keys.map(\.name).joined(separator: ", "))",
                    severity: .error
                ),
                LintingIssue(
                    reason: "The default configuration '\(settings.defaultConfiguration ?? "")' for target '\(target.name)' will be overridden by the project’s default configuration.",
                    severity: .warning
                ),
            ]
        )
    }
}
