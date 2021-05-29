import Foundation
import TSCBasic
import TuistCore
import TuistGraph

public final class IDETemplateMacrosMapper: ProjectMapping, WorkspaceMapping {
    public init() {}

    public func map(project: Project) throws -> (Project, [SideEffectDescriptor]) {
        (project, try sideEffects(for: project.ideTemplateMacros, to: project.xcodeProjPath))
    }

    public func map(workspace: WorkspaceWithProjects) throws -> (WorkspaceWithProjects, [SideEffectDescriptor]) {
        (workspace, try sideEffects(for: workspace.workspace.ideTemplateMacros, to: workspace.workspace.xcWorkspacePath))
    }

    private func sideEffects(
        for ideTemplateMacros: IDETemplateMacros?,
        to path: AbsolutePath
    ) throws -> [SideEffectDescriptor] {
        guard let ideTemplateMacros = ideTemplateMacros else { return [] }

        let encoder = PropertyListEncoder()
        let data = try encoder.encode(ideTemplateMacros)

        return [
            .file(FileDescriptor(
                path: path.appending(RelativePath("xcshareddata/IDETemplateMacros.plist")),
                contents: data
            )),
        ]
    }
}
