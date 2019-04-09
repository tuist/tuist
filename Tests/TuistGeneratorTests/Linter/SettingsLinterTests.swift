import Basic
import Foundation
import TuistCore
import XCTest
@testable import TuistCoreTesting
@testable import TuistGenerator

final class SettingsLinterTests: XCTestCase {
    var fileHandler: MockFileHandler!
    var subject: SettingsLinter!

    override func setUp() {
        super.setUp()
        fileHandler = try! MockFileHandler()
        subject = SettingsLinter(fileHandler: fileHandler)
    }

    func test_lint_project_when_config_files_are_missing() {
        // Given
        let debugPath = fileHandler.currentPath.appending(component: "Debug.xcconfig")
        let releasePath = fileHandler.currentPath.appending(component: "Release.xcconfig")
        let settings = Settings(configurations: [
            .debug: Configuration(xcconfig: debugPath),
            .release: Configuration(xcconfig: releasePath),
        ])
        let project = Project.test(settings: settings)

        // When
        let got = subject.lint(project: project)

        // Then
        XCTAssertEqual(got, [LintingIssue(reason: "Configuration file not found at path \(debugPath.asString)", severity: .error),
                             LintingIssue(reason: "Configuration file not found at path \(releasePath.asString)", severity: .error)])
    }

    func test_lint_target_when_config_files_are_missing() {
        // Given
        let debugPath = fileHandler.currentPath.appending(component: "Debug.xcconfig")
        let releasePath = fileHandler.currentPath.appending(component: "Release.xcconfig")
        let settings = Settings(configurations: [
            .debug: Configuration(xcconfig: debugPath),
            .release: Configuration(xcconfig: releasePath),
        ])
        let target = Target.test(settings: settings)

        // When
        let got = subject.lint(target: target)

        // Then
        XCTAssertEqual(got, [LintingIssue(reason: "Configuration file not found at path \(debugPath.asString)", severity: .error),
                             LintingIssue(reason: "Configuration file not found at path \(releasePath.asString)", severity: .error)])
    }

    func test_lint_project_when_no_configurations() {
        // Given
        let settings = Settings(base: ["A": "B"], configurations: [:])
        let project = Project.test(settings: settings)

        // When
        let got = subject.lint(project: project)

        // Then
        XCTAssertEqual(got, [LintingIssue(reason: "The project at path /test has no configurations", severity: .error)])
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
}
