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

    func test_lint_workspace_scheme_missingProjectPathInBuildAction() {
        // Given

        let buildAction = BuildAction.buildAction(targets: [.target("TargetA")])
        let scheme = Scheme.scheme(name: "MyScheme", buildAction: buildAction)
        let workspace = Workspace.test(schemes: [scheme])

        // When
        let results = subject.lint(workspace: workspace)

        // Then
        XCTAssertTrue(results.contains(LintingIssue(
            reason: """
            Workspace.swift: The target 'TargetA' in the buildAction of the scheme 'MyScheme' is missing the project path.
            Please specify the project path using .project(path:, target:).
            """,
            severity: .error
        )))
    }

    func test_lint_workspace_scheme_missingProjectPathInRunAction() {
        // Given
        let runAction = RunAction.runAction(expandVariableFromTarget: .target("TargetA"))
        let scheme = Scheme.scheme(name: "MyScheme", runAction: runAction)
        let workspace = Workspace.test(schemes: [scheme])

        // When
        let results = subject.lint(workspace: workspace)

        // Then
        XCTAssertTrue(results.contains(LintingIssue(
            reason: """
            Workspace.swift: The target 'TargetA' in the runAction of the scheme 'MyScheme' is missing the project path.
            Please specify the project path using .project(path:, target:).
            """,
            severity: .error
        )))
    }

    func test_lint_workspace_scheme_missingProjectPathInProfileAction() {
        // Given
        let profileAction = ProfileAction.profileAction(executable: .target("TargetA"))
        let scheme = Scheme.scheme(name: "MyScheme", profileAction: profileAction)
        let workspace = Workspace.test(schemes: [scheme])

        // When
        let results = subject.lint(workspace: workspace)

        // Then
        XCTAssertTrue(results.contains(LintingIssue(
            reason: """
            Workspace.swift: The target 'TargetA' in the profileAction of the scheme 'MyScheme' is missing the project path.
            Please specify the project path using .project(path:, target:).
            """,
            severity: .error
        )))
    }

    func test_lint_workspace_scheme_missingProjectPathInTestAction() {
        // Given
        let testAction = TestAction.test(targets: [.testableTarget(target: .target("TargetA"))])
        let scheme = Scheme.scheme(name: "MyScheme", testAction: testAction)
        let workspace = Workspace.test(schemes: [scheme])

        // When
        let results = subject.lint(workspace: workspace)

        // Then
        XCTAssertTrue(results.contains(LintingIssue(
            reason: """
            Workspace.swift: The target 'TargetA' in the testAction of the scheme 'MyScheme' is missing the project path.
            Please specify the project path using .project(path:, target:).
            """,
            severity: .error
        )))
    }

    func test_lint_workspace_scheme_missingProjectPathInBuildActionPreActions() {
        // Given
        let preActions = [ExecutionAction.executionAction(scriptText: "", target: .target("TargetA"))]
        let buildAction = BuildAction.buildAction(targets: [], preActions: preActions)
        let scheme = Scheme.scheme(name: "MyScheme", buildAction: buildAction)
        let workspace = Workspace.test(schemes: [scheme])

        // When
        let results = subject.lint(workspace: workspace)

        // Then
        XCTAssertTrue(results.contains(LintingIssue(
            reason: """
            Workspace.swift: The target 'TargetA' in the buildAction of the scheme 'MyScheme' is missing the project path.
            Please specify the project path using .project(path:, target:).
            """,
            severity: .error
        )))
    }

    func test_lint_workspace_scheme_missingProjectPathInRunActionPreActions() {
        // Given
        let preActions = [ExecutionAction.executionAction(scriptText: "", target: .target("TargetA"))]
        let runAction = RunAction.runAction(preActions: preActions)
        let scheme = Scheme.scheme(name: "MyScheme", runAction: runAction)
        let workspace = Workspace.test(schemes: [scheme])

        // When
        let results = subject.lint(workspace: workspace)

        // Then
        XCTAssertTrue(results.contains(LintingIssue(
            reason: """
            Workspace.swift: The target 'TargetA' in the runAction of the scheme 'MyScheme' is missing the project path.
            Please specify the project path using .project(path:, target:).
            """,
            severity: .error
        )))
    }

    func test_lint_workspace_scheme_missingProjectPathInProfileActionPreActions() {
        // Given
        let preActions = [ExecutionAction.executionAction(scriptText: "", target: .target("TargetA"))]
        let profileAction = ProfileAction.profileAction(preActions: preActions)
        let scheme = Scheme.scheme(name: "MyScheme", profileAction: profileAction)
        let workspace = Workspace.test(schemes: [scheme])

        // When
        let results = subject.lint(workspace: workspace)

        // Then
        XCTAssertTrue(results.contains(LintingIssue(
            reason: """
            Workspace.swift: The target 'TargetA' in the profileAction of the scheme 'MyScheme' is missing the project path.
            Please specify the project path using .project(path:, target:).
            """,
            severity: .error
        )))
    }

    func test_lint_workspace_scheme_missingProjectPathInTestActionPreActions() {
        // Given
        let preActions = [ExecutionAction.executionAction(scriptText: "", target: .target("TargetA"))]
        let testAction = TestAction.targets([], preActions: preActions)
        let scheme = Scheme.scheme(name: "MyScheme", testAction: testAction)
        let workspace = Workspace.test(schemes: [scheme])

        // When
        let results = subject.lint(workspace: workspace)

        // Then
        XCTAssertTrue(results.contains(LintingIssue(
            reason: """
            Workspace.swift: The target 'TargetA' in the testAction of the scheme 'MyScheme' is missing the project path.
            Please specify the project path using .project(path:, target:).
            """,
            severity: .error
        )))
    }

    func test_lint_workspace_scheme_missingProjectPathInRunActionPostActions() {
        // Given
        let postActions = [ExecutionAction.executionAction(scriptText: "", target: .target("TargetA"))]
        let runAction = RunAction.runAction(postActions: postActions)
        let scheme = Scheme.scheme(name: "MyScheme", runAction: runAction)
        let workspace = Workspace.test(schemes: [scheme])

        // When
        let results = subject.lint(workspace: workspace)

        // Then
        XCTAssertTrue(results.contains(LintingIssue(
            reason: """
            Workspace.swift: The target 'TargetA' in the runAction of the scheme 'MyScheme' is missing the project path.
            Please specify the project path using .project(path:, target:).
            """,
            severity: .error
        )))
    }

    func test_lint_workspace_scheme_missingProjectPathInProfileActionPostActions() {
        // Given
        let postActions = [ExecutionAction.executionAction(scriptText: "", target: .target("TargetA"))]
        let profileAction = ProfileAction.profileAction(postActions: postActions)
        let scheme = Scheme.scheme(name: "MyScheme", profileAction: profileAction)
        let workspace = Workspace.test(schemes: [scheme])

        // When
        let results = subject.lint(workspace: workspace)

        // Then
        XCTAssertTrue(results.contains(LintingIssue(
            reason: """
            Workspace.swift: The target 'TargetA' in the profileAction of the scheme 'MyScheme' is missing the project path.
            Please specify the project path using .project(path:, target:).
            """,
            severity: .error
        )))
    }

    func test_lint_workspace_scheme_missingProjectPathInTestActionPostActions() {
        // Given
        let postActions = [ExecutionAction.executionAction(scriptText: "", target: .target("TargetA"))]
        let testAction = TestAction.targets([], preActions: postActions)
        let scheme = Scheme.scheme(name: "MyScheme", testAction: testAction)
        let workspace = Workspace.test(schemes: [scheme])

        // When
        let results = subject.lint(workspace: workspace)

        // Then
        XCTAssertTrue(results.contains(LintingIssue(
            reason: """
            Workspace.swift: The target 'TargetA' in the testAction of the scheme 'MyScheme' is missing the project path.
            Please specify the project path using .project(path:, target:).
            """,
            severity: .error
        )))
    }
}
