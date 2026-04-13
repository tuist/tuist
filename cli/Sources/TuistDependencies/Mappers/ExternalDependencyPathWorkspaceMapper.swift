import FileSystem
import Foundation
import Path
import TuistConstants
import TuistCore
import TuistSupport
import XcodeGraph

public struct ExternalDependencyPathWorkspaceMapper: WorkspaceMapping {
    private let fileSystem: FileSysteming

    public init(fileSystem: FileSysteming = FileSystem()) {
        self.fileSystem = fileSystem
    }

    public func map(workspace: WorkspaceWithProjects) async throws -> (WorkspaceWithProjects, [SideEffectDescriptor]) {
        var workspace = workspace
        var mappedProjects: [(Project, [SideEffectDescriptor])] = []
        for project in workspace.projects {
            mappedProjects.append(try await map(project: project))
        }
        workspace.projects = mappedProjects.map(\.0)
        return (
            workspace,
            mappedProjects.flatMap(\.1)
        )
    }

    // MARK: - Helpers

    private func map(project: Project) async throws -> (Project, [SideEffectDescriptor]) {
        guard case .external = project.type,
              // We don't want to update local packages (which are defined outside the `checkouts` directory in `.build`
              project.path.parentDirectory.parentDirectory.basename == Constants.SwiftPackageManager.packageBuildDirectoryName
        else { return (project, []) }
        var project = project
        let xcodeProjBasename = project.xcodeProjPath.basename
        let derivedDirectory = project.path.parentDirectory.parentDirectory.appending(
            components: [
                Constants.DerivedDirectory.dependenciesDerivedDirectory,
                Constants.DerivedDirectory.dependenciesProjectDirectory,
                project.name,
            ]
        )
        // Remove any stale derived directory so it is recreated with the correct casing.
        // On case-insensitive filesystems (macOS), a leftover directory from a previous run
        // may have different casing, which Xcode 26+ flags as an error.
        if try await fileSystem.exists(derivedDirectory, isDirectory: true) {
            try await fileSystem.remove(derivedDirectory)
        }
        project.xcodeProjPath = derivedDirectory.appending(component: xcodeProjBasename)

        var base = project.settings.base
        // Keep the value if already defined
        if base["SRCROOT"] == nil {
            base["SRCROOT"] = SettingValue(stringLiteral: project.sourceRootPath
                .relative(to: project.xcodeProjPath.parentDirectory).pathString
            )
        }
        project.settings = project.settings.with(
            base: base
        )
        return (
            project,
            []
        )
    }
}
