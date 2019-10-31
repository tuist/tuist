
import ProjectDescription
import TuistSupport
import XCTest
@testable import TuistKit

class ManifestLinterTests: XCTestCase {
    var subject: ManifestLinter!

    override func setUp() {
        subject = ManifestLinter()
    }

    // MARK: - Tests

    func test_lint_project_duplicateConfigurationNames() {
        // Given
        let settings = Settings(configurations: [
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
        XCTAssertEqual(results, [
            LintingIssue(reason: "The configuration 'A' is declared multiple times within 'MyProject' settings. The last declared configuration will be used.", severity: .warning),
            LintingIssue(reason: "The configuration 'B' is declared multiple times within 'MyProject' settings. The last declared configuration will be used.", severity: .warning),
        ])
    }

    func test_lint_target_duplicateConfigurationNames() {
        // Given
        let settings = Settings(configurations: [
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
        XCTAssertEqual(results, [
            LintingIssue(reason: "The configuration 'A' is declared multiple times within 'MyFramework' settings. The last declared configuration will be used.", severity: .warning),
            LintingIssue(reason: "The configuration 'B' is declared multiple times within 'MyFramework' settings. The last declared configuration will be used.", severity: .warning),
        ])
    }
}
