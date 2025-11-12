import FileSystem
import Foundation
import Path
import TuistCore
import TuistSupport
import XcodeGraph

public protocol ManifestMapperLinting {
    func lint(workspace: Workspace, fileSystem: FileSysteming) async throws -> [LintingIssue]
    func lint(project: Project, fileSystem: FileSysteming) async throws -> [LintingIssue]
}

public final class ManifestMapperLinter: ManifestMapperLinting {
    public init() {}

    public func lint(workspace: Workspace, fileSystem: FileSysteming) async throws -> [LintingIssue] {
        var issues: [LintingIssue] = []

        // Validate workspace projects
        if workspace.projects.isEmpty {
            issues.append(
                LintingIssue(
                    reason: "No projects found at: \(workspace.path.pathString)",
                    severity: .warning
                )
            )
        }

        // Validate workspace additional files
        for file in workspace.additionalFiles {
            issues.append(contentsOf: try await validateFileElement(file, fileSystem: fileSystem))
        }

        return issues
    }

    public func lint(project: Project, fileSystem: FileSysteming) async throws -> [LintingIssue] {
        var issues: [LintingIssue] = []

        // Validate project file elements
        for fileElement in project.fileElements {
            issues.append(contentsOf: try await validateFileElement(fileElement, fileSystem: fileSystem))
        }

        // Validate resources in targets
        for target in project.targets.values {
            issues.append(contentsOf: try await validateTargetResources(target, fileSystem: fileSystem))
        }

        return issues
    }

    private func validateFileElement(_ element: FileElement, fileSystem: FileSysteming) async throws -> [LintingIssue] {
        var issues: [LintingIssue] = []

        switch element {
        case let .file(path):
            if !(try await fileSystem.exists(path)) {
                issues.append(
                    LintingIssue(
                        reason: "No files found at: \(path.pathString)",
                        severity: .warning
                    )
                )
            }

        case let .folderReference(path):
            if !(try await fileSystem.exists(path)) {
                issues.append(
                    LintingIssue(
                        reason: "\(path.pathString) does not exist",
                        severity: .warning
                    )
                )
            } else if !FileHandler.shared.isFolder(path) {
                issues.append(
                    LintingIssue(
                        reason: "\(path.pathString) is not a directory - folder reference paths need to point to directories",
                        severity: .warning
                    )
                )
            }
        }

        return issues
    }

    private func validateTargetResources(_ target: Target, fileSystem: FileSysteming) async throws -> [LintingIssue] {
        var issues: [LintingIssue] = []

        // Validate resource file elements
        for resource in target.resources.resources {
            issues.append(contentsOf: try await validateResourceFileElement(resource, fileSystem: fileSystem))
        }

        // Validate copy files
        for copyFile in target.copyFiles {
            for element in copyFile.files {
                issues.append(contentsOf: try await validateCopyFileElement(element, fileSystem: fileSystem))
            }
        }

        return issues
    }

    private func validateResourceFileElement(
        _ element: ResourceFileElement,
        fileSystem: FileSysteming
    ) async throws -> [LintingIssue] {
        var issues: [LintingIssue] = []

        switch element {
        case let .file(path, _, _):
            if !(try await fileSystem.exists(path)) {
                issues.append(
                    LintingIssue(
                        reason: "No files found at: \(path.pathString)",
                        severity: .warning
                    )
                )
            }

        case let .folderReference(path, _, _):
            if !(try await fileSystem.exists(path)) {
                issues.append(
                    LintingIssue(
                        reason: "\(path.pathString) does not exist",
                        severity: .warning
                    )
                )
            } else if !FileHandler.shared.isFolder(path) {
                issues.append(
                    LintingIssue(
                        reason: "\(path.pathString) is not a directory - folder reference paths need to point to directories",
                        severity: .warning
                    )
                )
            }
        }

        return issues
    }

    private func validateCopyFileElement(
        _ element: CopyFileElement,
        fileSystem: FileSysteming
    ) async throws -> [LintingIssue] {
        var issues: [LintingIssue] = []

        switch element {
        case let .file(path, _, _):
            if !(try await fileSystem.exists(path)) {
                issues.append(
                    LintingIssue(
                        reason: "No files found at: \(path.pathString)",
                        severity: .warning
                    )
                )
            }

        case let .folderReference(path, _, _):
            if !(try await fileSystem.exists(path)) {
                issues.append(
                    LintingIssue(
                        reason: "\(path.pathString) does not exist",
                        severity: .warning
                    )
                )
            } else if !FileHandler.shared.isFolder(path) {
                issues.append(
                    LintingIssue(
                        reason: "\(path.pathString) is not a directory - folder reference paths need to point to directories",
                        severity: .warning
                    )
                )
            }
        }

        return issues
    }
}
