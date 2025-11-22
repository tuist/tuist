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

        if workspace.projects.isEmpty {
            issues.append(
                LintingIssue(
                    reason: "The workspace at '\(workspace.path.pathString)' has no projects",
                    severity: .warning
                )
            )
        }

        for file in workspace.additionalFiles {
            issues.append(contentsOf: try await validateFileElement(file, context: "workspace", fileSystem: fileSystem))
        }

        return issues
    }

    public func lint(project: Project, fileSystem: FileSysteming) async throws -> [LintingIssue] {
        var issues: [LintingIssue] = []

        for fileElement in project.fileElements {
            issues.append(
                contentsOf: try await validateFileElement(
                    fileElement,
                    context: "project '\(project.name)'",
                    fileSystem: fileSystem
                )
            )
        }

        for target in project.targets.values {
            issues.append(contentsOf: try await validateTargetResources(target, fileSystem: fileSystem))
        }

        return issues
    }

    private func validateFileElement(
        _ element: FileElement,
        context: String,
        fileSystem: FileSysteming
    ) async throws -> [LintingIssue] {
        var issues: [LintingIssue] = []

        switch element {
        case let .file(path):
            if !(try await fileSystem.exists(path)) {
                issues.append(
                    LintingIssue(
                        reason: "The \(context) references a file at path '\(path.pathString)' that doesn't exist",
                        severity: .warning
                    )
                )
            }

        case let .folderReference(path):
            if !(try await fileSystem.exists(path)) {
                issues.append(
                    LintingIssue(
                        reason: "The \(context) references a folder at path '\(path.pathString)' that doesn't exist",
                        severity: .warning
                    )
                )
            } else if !(try await fileSystem.isDirectory(path)) {
                issues.append(
                    LintingIssue(
                        reason: "The \(context) references '\(path.pathString)' as a folder but it is not a directory",
                        severity: .warning
                    )
                )
            }
        }

        return issues
    }

    private func validateTargetResources(_ target: Target, fileSystem: FileSysteming) async throws -> [LintingIssue] {
        var issues: [LintingIssue] = []

        for resource in target.resources.resources {
            issues.append(
                contentsOf: try await validateResourceFileElement(
                    resource,
                    targetName: target.name,
                    fileSystem: fileSystem
                )
            )
        }

        for copyFile in target.copyFiles {
            for element in copyFile.files {
                issues.append(
                    contentsOf: try await validateCopyFileElement(
                        element,
                        targetName: target.name,
                        fileSystem: fileSystem
                    )
                )
            }
        }

        return issues
    }

    private func validateResourceFileElement(
        _ element: ResourceFileElement,
        targetName: String,
        fileSystem: FileSysteming
    ) async throws -> [LintingIssue] {
        var issues: [LintingIssue] = []

        switch element {
        case let .file(path, _, _):
            if !(try await fileSystem.exists(path)) {
                issues.append(
                    LintingIssue(
                        reason: "The target '\(targetName)' references a resource file at path '\(path.pathString)' that doesn't exist",
                        severity: .warning
                    )
                )
            }

        case let .folderReference(path, _, _):
            if !(try await fileSystem.exists(path)) {
                issues.append(
                    LintingIssue(
                        reason: "The target '\(targetName)' references a resource folder at path '\(path.pathString)' that doesn't exist",
                        severity: .warning
                    )
                )
            } else if !(try await fileSystem.isDirectory(path)) {
                issues.append(
                    LintingIssue(
                        reason: "The target '\(targetName)' references '\(path.pathString)' as a resource folder but it is not a directory",
                        severity: .warning
                    )
                )
            }
        }

        return issues
    }

    private func validateCopyFileElement(
        _ element: CopyFileElement,
        targetName: String,
        fileSystem: FileSysteming
    ) async throws -> [LintingIssue] {
        var issues: [LintingIssue] = []

        switch element {
        case let .file(path, _, _):
            if !(try await fileSystem.exists(path)) {
                issues.append(
                    LintingIssue(
                        reason: "The target '\(targetName)' references a copy file at path '\(path.pathString)' that doesn't exist",
                        severity: .warning
                    )
                )
            }

        case let .folderReference(path, _, _):
            if !(try await fileSystem.exists(path)) {
                issues.append(
                    LintingIssue(
                        reason: "The target '\(targetName)' references a copy folder at path '\(path.pathString)' that doesn't exist",
                        severity: .warning
                    )
                )
            } else if !(try await fileSystem.isDirectory(path)) {
                issues.append(
                    LintingIssue(
                        reason: "The target '\(targetName)' references '\(path.pathString)' as a copy folder but it is not a directory",
                        severity: .warning
                    )
                )
            }
        }

        return issues
    }
}
