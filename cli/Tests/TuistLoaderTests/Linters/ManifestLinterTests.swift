import FileSystem
import Path
import ProjectDescription
import TuistCore
import TuistSupport
import XCTest

@testable import TuistLoader
@testable import TuistTesting

final class ManifestLinterTests: TuistUnitTestCase {
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

    func test_lint_project_duplicateConfigurationNames() async throws {
        // Given
        let settings: Settings = .settings(configurations: [
            .debug(name: "A"),
            .debug(name: "A"),
            .release(name: "B"),
            .release(name: "B"),
            .release(name: "C"),
        ])

        let project = Project.test(name: "MyProject", settings: settings)
        let path = try temporaryPath()

        // When
        let results = try await subject.lint(project: project, path: path)

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

    func test_lint_target_duplicateConfigurationNames() async throws {
        // Given
        let settings: Settings = .settings(configurations: [
            .debug(name: "A"),
            .debug(name: "A"),
            .release(name: "B"),
            .release(name: "B"),
            .release(name: "C"),
        ])

        let project = Project.test(targets: [.test(name: "MyFramework", settings: settings)])
        let path = try temporaryPath()

        // When
        let results = try await subject.lint(project: project, path: path)

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

    func test_lint_project_duplicateTargetNames() async throws {
        // Given
        let targetA = Target.test(name: "A")
        let targetADuplicated = Target.test(name: "A")
        let targetB = Target.test(name: "B")
        let project = Project.test(targets: [targetA, targetADuplicated, targetB])
        let path = try temporaryPath()

        // When
        let results = try await subject.lint(project: project, path: path)

        // Then
        XCTAssertTrue(results.contains(LintingIssue(
            reason: "The target 'A' is declared multiple times within 'Project' project.",
            severity: .error
        )))
    }

    func test_lint_workspace_scheme_missingProjectPathInBuildAction() async throws {
        // Given

        let buildAction = BuildAction.buildAction(targets: [.target("TargetA")])
        let scheme = Scheme.scheme(name: "MyScheme", buildAction: buildAction)
        let workspace = Workspace.test(schemes: [scheme])
        let path = try temporaryPath()

        // When
        let results = try await subject.lint(workspace: workspace, path: path)

        // Then
        XCTAssertTrue(results.contains(LintingIssue(
            reason: """
            Workspace.swift: The target 'TargetA' in the buildAction of the scheme 'MyScheme' is missing the project path.
            Please specify the project path using .project(path:, target:).
            """,
            severity: .error
        )))
    }

    func test_lint_workspace_scheme_missingProjectPathInRunAction() async throws {
        // Given
        let runAction = RunAction.runAction(expandVariableFromTarget: .target("TargetA"))
        let scheme = Scheme.scheme(name: "MyScheme", runAction: runAction)
        let workspace = Workspace.test(schemes: [scheme])
        let path = try temporaryPath()

        // When
        let results = try await subject.lint(workspace: workspace, path: path)

        // Then
        XCTAssertTrue(results.contains(LintingIssue(
            reason: """
            Workspace.swift: The target 'TargetA' in the runAction of the scheme 'MyScheme' is missing the project path.
            Please specify the project path using .project(path:, target:).
            """,
            severity: .error
        )))
    }

    func test_lint_workspace_scheme_missingProjectPathInProfileAction() async throws {
        // Given
        let profileAction = ProfileAction.profileAction(executable: .target("TargetA"))
        let scheme = Scheme.scheme(name: "MyScheme", profileAction: profileAction)
        let workspace = Workspace.test(schemes: [scheme])
        let path = try temporaryPath()

        // When
        let results = try await subject.lint(workspace: workspace, path: path)

        // Then
        XCTAssertTrue(results.contains(LintingIssue(
            reason: """
            Workspace.swift: The target 'TargetA' in the profileAction of the scheme 'MyScheme' is missing the project path.
            Please specify the project path using .project(path:, target:).
            """,
            severity: .error
        )))
    }

    func test_lint_workspace_scheme_missingProjectPathInTestAction() async throws {
        // Given
        let testAction = TestAction.test(targets: [.testableTarget(target: .target("TargetA"))])
        let scheme = Scheme.scheme(name: "MyScheme", testAction: testAction)
        let workspace = Workspace.test(schemes: [scheme])
        let path = try temporaryPath()

        // When
        let results = try await subject.lint(workspace: workspace, path: path)

        // Then
        XCTAssertTrue(results.contains(LintingIssue(
            reason: """
            Workspace.swift: The target 'TargetA' in the testAction of the scheme 'MyScheme' is missing the project path.
            Please specify the project path using .project(path:, target:).
            """,
            severity: .error
        )))
    }

    func test_lint_workspace_scheme_missingProjectPathInBuildActionPreActions() async throws {
        // Given
        let preActions = [ExecutionAction.executionAction(scriptText: "", target: .target("TargetA"))]
        let buildAction = BuildAction.buildAction(targets: [], preActions: preActions)
        let scheme = Scheme.scheme(name: "MyScheme", buildAction: buildAction)
        let workspace = Workspace.test(schemes: [scheme])
        let path = try temporaryPath()

        // When
        let results = try await subject.lint(workspace: workspace, path: path)

        // Then
        XCTAssertTrue(results.contains(LintingIssue(
            reason: """
            Workspace.swift: The target 'TargetA' in the buildAction of the scheme 'MyScheme' is missing the project path.
            Please specify the project path using .project(path:, target:).
            """,
            severity: .error
        )))
    }

    func test_lint_workspace_scheme_missingProjectPathInRunActionPreActions() async throws {
        // Given
        let preActions = [ExecutionAction.executionAction(scriptText: "", target: .target("TargetA"))]
        let runAction = RunAction.runAction(preActions: preActions)
        let scheme = Scheme.scheme(name: "MyScheme", runAction: runAction)
        let workspace = Workspace.test(schemes: [scheme])
        let path = try temporaryPath()

        // When
        let results = try await subject.lint(workspace: workspace, path: path)

        // Then
        XCTAssertTrue(results.contains(LintingIssue(
            reason: """
            Workspace.swift: The target 'TargetA' in the runAction of the scheme 'MyScheme' is missing the project path.
            Please specify the project path using .project(path:, target:).
            """,
            severity: .error
        )))
    }

    func test_lint_workspace_scheme_missingProjectPathInProfileActionPreActions() async throws {
        // Given
        let preActions = [ExecutionAction.executionAction(scriptText: "", target: .target("TargetA"))]
        let profileAction = ProfileAction.profileAction(preActions: preActions)
        let scheme = Scheme.scheme(name: "MyScheme", profileAction: profileAction)
        let workspace = Workspace.test(schemes: [scheme])
        let path = try temporaryPath()

        // When
        let results = try await subject.lint(workspace: workspace, path: path)

        // Then
        XCTAssertTrue(results.contains(LintingIssue(
            reason: """
            Workspace.swift: The target 'TargetA' in the profileAction of the scheme 'MyScheme' is missing the project path.
            Please specify the project path using .project(path:, target:).
            """,
            severity: .error
        )))
    }

    func test_lint_workspace_scheme_missingProjectPathInTestActionPreActions() async throws {
        // Given
        let preActions = [ExecutionAction.executionAction(scriptText: "", target: .target("TargetA"))]
        let testAction = TestAction.targets([], preActions: preActions)
        let scheme = Scheme.scheme(name: "MyScheme", testAction: testAction)
        let workspace = Workspace.test(schemes: [scheme])
        let path = try temporaryPath()

        // When
        let results = try await subject.lint(workspace: workspace, path: path)

        // Then
        XCTAssertTrue(results.contains(LintingIssue(
            reason: """
            Workspace.swift: The target 'TargetA' in the testAction of the scheme 'MyScheme' is missing the project path.
            Please specify the project path using .project(path:, target:).
            """,
            severity: .error
        )))
    }

    func test_lint_workspace_scheme_missingProjectPathInRunActionPostActions() async throws {
        // Given
        let postActions = [ExecutionAction.executionAction(scriptText: "", target: .target("TargetA"))]
        let runAction = RunAction.runAction(postActions: postActions)
        let scheme = Scheme.scheme(name: "MyScheme", runAction: runAction)
        let workspace = Workspace.test(schemes: [scheme])
        let path = try temporaryPath()

        // When
        let results = try await subject.lint(workspace: workspace, path: path)

        // Then
        XCTAssertTrue(results.contains(LintingIssue(
            reason: """
            Workspace.swift: The target 'TargetA' in the runAction of the scheme 'MyScheme' is missing the project path.
            Please specify the project path using .project(path:, target:).
            """,
            severity: .error
        )))
    }

    func test_lint_workspace_scheme_missingProjectPathInProfileActionPostActions() async throws {
        // Given
        let postActions = [ExecutionAction.executionAction(scriptText: "", target: .target("TargetA"))]
        let profileAction = ProfileAction.profileAction(postActions: postActions)
        let scheme = Scheme.scheme(name: "MyScheme", profileAction: profileAction)
        let workspace = Workspace.test(schemes: [scheme])
        let path = try temporaryPath()

        // When
        let results = try await subject.lint(workspace: workspace, path: path)

        // Then
        XCTAssertTrue(results.contains(LintingIssue(
            reason: """
            Workspace.swift: The target 'TargetA' in the profileAction of the scheme 'MyScheme' is missing the project path.
            Please specify the project path using .project(path:, target:).
            """,
            severity: .error
        )))
    }

    func test_lint_workspace_scheme_missingProjectPathInTestActionPostActions() async throws {
        // Given
        let postActions = [ExecutionAction.executionAction(scriptText: "", target: .target("TargetA"))]
        let testAction = TestAction.targets([], preActions: postActions)
        let scheme = Scheme.scheme(name: "MyScheme", testAction: testAction)
        let workspace = Workspace.test(schemes: [scheme])
        let path = try temporaryPath()

        // When
        let results = try await subject.lint(workspace: workspace, path: path)

        // Then
        XCTAssertTrue(results.contains(LintingIssue(
            reason: """
            Workspace.swift: The target 'TargetA' in the testAction of the scheme 'MyScheme' is missing the project path.
            Please specify the project path using .project(path:, target:).
            """,
            severity: .error
        )))
    }

    // MARK: - File Element Linting Tests

    func test_lint_project_fileElementNotFound() async throws {
        // Given
        let path = try temporaryPath()
        let nonExistentPath = path.appending(component: "NonExistent.swift")
        let project = Project.test(
            targets: [
                .test(additionalFiles: [.glob(pattern: .path(nonExistentPath.pathString))]),
            ]
        )

        // When
        let results = try await subject.lint(project: project, path: path)

        // Then
        XCTAssertTrue(results.contains(LintingIssue(
            reason: "No files found at: \(nonExistentPath.pathString)",
            severity: .warning
        )))
    }

    func test_lint_project_folderReferenceNotFound() async throws {
        // Given
        let path = try temporaryPath()
        let nonExistentPath = path.appending(component: "NonExistentFolder")
        let project = Project.test(
            targets: [
                .test(additionalFiles: [.folderReference(path: .path(nonExistentPath.pathString))]),
            ]
        )

        // When
        let results = try await subject.lint(project: project, path: path)

        // Then
        XCTAssertTrue(results.contains(LintingIssue(
            reason: "\(nonExistentPath.pathString) does not exist",
            severity: .warning
        )))
    }

    func test_lint_project_folderReferenceIsNotDirectory() async throws {
        // Given
        let path = try temporaryPath()
        let filePath = path.appending(component: "File.txt")
        try FileHandler.shared.touch(filePath)
        let project = Project.test(
            targets: [
                .test(additionalFiles: [.folderReference(path: .path(filePath.pathString))]),
            ]
        )

        // When
        let results = try await subject.lint(project: project, path: path)

        // Then
        XCTAssertTrue(results.contains(LintingIssue(
            reason: "\(filePath.pathString) is not a directory - folder reference paths need to point to directories",
            severity: .warning
        )))
    }

    func test_lint_project_directoryUsedAsGlob() async throws {
        // Given
        let path = try temporaryPath()
        let folderPath = path.appending(component: "Folder")
        try FileHandler.shared.createFolder(folderPath)
        let project = Project.test(
            targets: [
                .test(additionalFiles: [.glob(pattern: .path(folderPath.pathString))]),
            ]
        )

        // When
        let results = try await subject.lint(project: project, path: path)

        // Then
        XCTAssertTrue(results.contains(LintingIssue(
            reason: "'\(folderPath.pathString)' is a directory, try using: '\(folderPath.pathString)/**' to list its files",
            severity: .warning
        )))
    }

    func test_lint_project_validFileElement() async throws {
        // Given
        let path = try temporaryPath()
        let filePath = path.appending(component: "File.swift")
        try FileHandler.shared.touch(filePath)
        let project = Project.test(
            targets: [
                .test(additionalFiles: [.glob(pattern: .path(filePath.pathString))]),
            ]
        )

        // When
        let results = try await subject.lint(project: project, path: path)

        // Then
        XCTAssertFalse(results.contains { $0.reason.contains(filePath.pathString) })
    }

    func test_lint_project_validFolderReference() async throws {
        // Given
        let path = try temporaryPath()
        let folderPath = path.appending(component: "Folder")
        try FileHandler.shared.createFolder(folderPath)
        let project = Project.test(
            targets: [
                .test(additionalFiles: [.folderReference(path: .path(folderPath.pathString))]),
            ]
        )

        // When
        let results = try await subject.lint(project: project, path: path)

        // Then
        XCTAssertFalse(results.contains { $0.reason.contains(folderPath.pathString) })
    }
}
