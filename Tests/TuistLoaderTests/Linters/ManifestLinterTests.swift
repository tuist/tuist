import ProjectDescription
import TuistCore
import TuistSupport
import XCTest

@testable import TuistLoader

class ManifestLinterTests: XCTestCase {
    var subject: ManifestLinter!

    override func setUp() {
        super.setUp()
        subject = ManifestLinter()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    // MARK: - Tests

    func test_lint_project_duplicateConfigurationNames() {
        // Given
        let settings: Settings = .settings(configurations: [
            .debug(name: "A"),
            .debug(name: "A"),
            .release(name: "B"),
            .release(name: "B"),
            .release(name: "C"),
        ])

        let project = Project.test(name: "MyProject", settings: settings)

        // When
        let results = subject.lint(project: project)

        // Then
        XCTAssertTrue(results.contains(LintingIssue(
            reason: "The configuration 'A' is declared multiple times within 'MyProject' settings. The last declared configuration will be used.",
            severity: .warning
        )))
        XCTAssertTrue(results.contains(LintingIssue(
            reason: "The configuration 'B' is declared multiple times within 'MyProject' settings. The last declared configuration will be used.",
            severity: .warning
        )))
    }

    func test_lint_target_duplicateConfigurationNames() {
        // Given
        let settings: Settings = .settings(configurations: [
            .debug(name: "A"),
            .debug(name: "A"),
            .release(name: "B"),
            .release(name: "B"),
            .release(name: "C"),
        ])

        let project = Project.test(targets: [.test(name: "MyFramework", settings: settings)])

        // When
        let results = subject.lint(project: project)

        // Then
        XCTAssertTrue(results.contains(LintingIssue(
            reason: "The configuration 'A' is declared multiple times within 'MyFramework' settings. The last declared configuration will be used.",
            severity: .warning
        )))
        XCTAssertTrue(results.contains(LintingIssue(
            reason: "The configuration 'B' is declared multiple times within 'MyFramework' settings. The last declared configuration will be used.",
            severity: .warning
        )))
    }

    func test_lint_project_duplicateTargetNames() throws {
        // Given
        let targetA = Target.test(name: "A")
        let targetADuplicated = Target.test(name: "A")
        let targetB = Target.test(name: "B")
        let project = Project.test(targets: [targetA, targetADuplicated, targetB])

        // When
        let results = subject.lint(project: project)

        // Then
        XCTAssertTrue(results.contains(LintingIssue(
            reason: "The target 'A' is declared multiple times within 'Project' project.",
            severity: .error
        )))
    }
}
