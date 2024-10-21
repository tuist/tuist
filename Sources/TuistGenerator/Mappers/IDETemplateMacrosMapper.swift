import Foundation
import Path
import TuistCore
import XcodeGraph

public final class IDETemplateMacrosMapper: ProjectMapping, WorkspaceMapping {
    public init() {}

    public func map(project: Project) throws -> (Project, [SideEffectDescriptor]) {
        logger.debug("Transforming project \(project.name): Generating xcshareddata/IDETemplateMacros.plist")
        return (project, try sideEffects(for: project.ideTemplateMacros, to: project.xcodeProjPath))
    }

    public func map(workspace: WorkspaceWithProjects) throws -> (WorkspaceWithProjects, [SideEffectDescriptor]) {
        logger.debug("Transforming workspace \(workspace.workspace.name): Generating xcshareddata/IDETemplateMacros.plist")
        return (workspace, try sideEffects(for: workspace.workspace.ideTemplateMacros, to: workspace.workspace.xcWorkspacePath))
    }

    private func sideEffects(
        for ideTemplateMacros: IDETemplateMacros?,
        to path: AbsolutePath
    ) throws -> [SideEffectDescriptor] {
        guard let ideTemplateMacros else { return [] }

        let encoder = PropertyListEncoder()
        let data = try encoder.encode(ideTemplateMacros)

        return [
            .file(FileDescriptor(
                // swiftlint:disable:next force_try
                path: path.appending(try! RelativePath(validating: "xcshareddata/IDETemplateMacros.plist")),
                contents: data
            )),
        ]
    }
}
