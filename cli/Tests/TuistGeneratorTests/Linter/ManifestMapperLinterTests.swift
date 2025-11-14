import FileSystem
import Foundation
import Path
import Testing
import TuistCore
import TuistSupport
import XcodeGraph

@testable import FileSystemTesting
@testable import TuistGenerator
@testable import TuistSupportTesting

final class ManifestMapperLinterTests {
    private var fileSystem: FileSysteming!
    private var subject: ManifestMapperLinter!

    init() {
        fileSystem = FileSystem()
        subject = ManifestMapperLinter()
    }

    @Test(.inTemporaryDirectory)
    func test_lint_workspace_with_no_projects() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let workspace = Workspace.test(
            path: temporaryDirectory,
            projects: []
        )

        let issues = try await subject.lint(workspace: workspace, fileSystem: fileSystem)

        #expect(issues.count == 1)
        #expect(issues.first?.reason == "No projects found at: \(temporaryDirectory.pathString)")
        #expect(issues.first?.severity == .warning)
    }

    @Test(.inTemporaryDirectory)
    func test_lint_workspace_with_projects() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let projectPath = temporaryDirectory.appending(component: "Project")
        let workspace = Workspace.test(
            path: temporaryDirectory,
            projects: [projectPath]
        )

        let issues = try await subject.lint(workspace: workspace, fileSystem: fileSystem)

        #expect(issues.isEmpty)
    }

    @Test(.inTemporaryDirectory)
    func test_lint_workspace_with_missing_additional_files() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let missingFile = temporaryDirectory.appending(component: "missing.txt")
        let workspace = Workspace.test(
            path: temporaryDirectory,
            projects: [temporaryDirectory],
            additionalFiles: [.file(path: missingFile)]
        )

        let issues = try await subject.lint(workspace: workspace, fileSystem: fileSystem)

        #expect(issues.count == 1)
        #expect(issues.first?.reason == "No files found at: \(missingFile.pathString)")
        #expect(issues.first?.severity == .warning)
    }

    @Test(.inTemporaryDirectory)
    func test_lint_project_with_missing_file_element() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let missingFile = temporaryDirectory.appending(component: "missing.txt")
        let project = Project.test(
            path: temporaryDirectory,
            fileElements: [.file(path: missingFile)]
        )

        let issues = try await subject.lint(project: project, fileSystem: fileSystem)

        #expect(issues.count == 1)
        #expect(issues.first?.reason == "No files found at: \(missingFile.pathString)")
        #expect(issues.first?.severity == .warning)
    }

    @Test(.inTemporaryDirectory)
    func test_lint_project_with_invalid_folder_reference() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let filePath = temporaryDirectory.appending(component: "file.txt")

        try await fileSystem.touch(filePath)

        let project = Project.test(
            path: temporaryDirectory,
            fileElements: [.folderReference(path: filePath)]
        )

        let issues = try await subject.lint(project: project, fileSystem: fileSystem)

        #expect(issues.count == 1)
        #expect(
            issues.first?.reason ==
                "\(filePath.pathString) is not a directory - folder reference paths need to point to directories"
        )
        #expect(issues.first?.severity == .warning)
    }

    @Test(.inTemporaryDirectory)
    func test_lint_target_with_missing_resource_files() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let missingResource = temporaryDirectory.appending(component: "Assets.xcassets")

        let target = Target.test(
            name: "App",
            resources: .resources([
                .file(path: missingResource, tags: [], inclusionCondition: nil),
            ])
        )

        let project = Project.test(
            path: temporaryDirectory,
            targets: [target]
        )

        let issues = try await subject.lint(project: project, fileSystem: fileSystem)

        #expect(issues.count == 1)
        #expect(issues.first?.reason == "No files found at: \(missingResource.pathString)")
        #expect(issues.first?.severity == .warning)
    }

    @Test(.inTemporaryDirectory)
    func test_lint_target_with_missing_copy_files() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let missingFile = temporaryDirectory.appending(component: "Framework.framework")

        let target = Target.test(
            name: "App",
            copyFiles: [
                CopyFilesAction(
                    name: "Embed Frameworks",
                    destination: .frameworks,
                    files: [.file(path: missingFile, condition: nil, codeSignOnCopy: true)]
                ),
            ]
        )

        let project = Project.test(
            path: temporaryDirectory,
            targets: [target]
        )

        let issues = try await subject.lint(project: project, fileSystem: fileSystem)

        #expect(issues.count == 1)
        #expect(issues.first?.reason == "No files found at: \(missingFile.pathString)")
        #expect(issues.first?.severity == .warning)
    }

    @Test(.inTemporaryDirectory)
    func test_lint_target_with_valid_folder_reference() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let folderPath = temporaryDirectory.appending(component: "Resources")

        try await fileSystem.makeDirectory(at: folderPath)

        let target = Target.test(
            name: "App",
            resources: .resources([
                .folderReference(path: folderPath, tags: [], inclusionCondition: nil),
            ])
        )

        let project = Project.test(
            path: temporaryDirectory,
            targets: [target]
        )

        let issues = try await subject.lint(project: project, fileSystem: fileSystem)

        #expect(issues.isEmpty)
    }

    @Test(.inTemporaryDirectory)
    func test_lint_no_issues_when_all_files_exist() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let existingFile = temporaryDirectory.appending(component: "existing.txt")
        let existingFolder = temporaryDirectory.appending(component: "Resources")

        try await fileSystem.touch(existingFile)
        try await fileSystem.makeDirectory(at: existingFolder)

        let target = Target.test(
            name: "App",
            resources: .resources([
                .file(path: existingFile, tags: [], inclusionCondition: nil),
                .folderReference(path: existingFolder, tags: [], inclusionCondition: nil),
            ])
        )

        let project = Project.test(
            path: temporaryDirectory,
            fileElements: [
                .file(path: existingFile),
                .folderReference(path: existingFolder),
            ],
            targets: [target]
        )

        let issues = try await subject.lint(project: project, fileSystem: fileSystem)

        #expect(issues.isEmpty)
    }
}
