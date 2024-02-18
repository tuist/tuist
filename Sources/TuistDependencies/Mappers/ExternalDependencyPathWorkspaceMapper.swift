import Foundation
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport

public final class ExternalDependencyPathWorkspaceMapper: WorkspaceMapping {
    public init() {}

    public func map(workspace: WorkspaceWithProjects) throws -> (WorkspaceWithProjects, [SideEffectDescriptor]) {
        var workspace = workspace
        let mappedProjects = try workspace.projects.map(map(project:))
        workspace.projects = mappedProjects.map(\.0)
        return (
            workspace,
            mappedProjects.flatMap(\.1)
        )
    }

    // MARK: - Helpers

    private func map(project: Project) throws -> (Project, [SideEffectDescriptor]) {
        guard project.isExternal,
              // We don't want to update local packages (which are defined outside the `checkouts` directory in `.build`
              project.path.parentDirectory.parentDirectory.basename == Constants.SwiftPackageManager.packageBuildDirectoryName
        else { return (project, []) }
        var project = project
        let xcodeProjBasename = project.xcodeProjPath.basename
        let derivedDirectory = project.path.parentDirectory.parentDirectory.appending(
            components: Constants.DerivedDirectory.dependenciesDerivedDirectory, project.name
        )
        project.xcodeProjPath = derivedDirectory.appending(component: xcodeProjBasename)

        var base = project.settings.base
        // Keep the value if already defined
        if base["SRCROOT"] == nil {
            base["SRCROOT"] = SettingValue(stringLiteral: project.sourceRootPath.pathString)
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
