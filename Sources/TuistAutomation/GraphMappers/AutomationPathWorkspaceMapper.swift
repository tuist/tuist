import Foundation
import TuistCore
import TuistSupport

/// Updates path of workspace to point to where automation workspace should be generated
public final class AutomationPathWorkspaceMapper: WorkspaceMapping {
    private let contentHasher: ContentHashing
    
    public init(
        contentHasher: ContentHashing = ContentHasher()
    ) {
        self.contentHasher = contentHasher
    }
    
    public func map(workspace: WorkspaceWithProjects) throws -> (WorkspaceWithProjects, [SideEffectDescriptor]) {
        var workspace = workspace
        let pathHash = try contentHasher.hash(workspace.workspace.path.pathString)
        let projectsDirectory = Environment.shared.projectsCacheDirectory
            .appending(component: workspace.workspace.name + "-" + pathHash)
        workspace.workspace.path = projectsDirectory
        return (
            workspace,
            [
                .directory(
                    DirectoryDescriptor(
                        path: projectsDirectory,
                        state: .present
                    )
                ),
            ]
        )
    }
}
