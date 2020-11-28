import Foundation
import TuistCore
import TuistSupport
import TSCBasic

/// Updates path of workspace to point to where automation workspace should be generated
public final class AutomationPathWorkspaceMapper: WorkspaceMapping {
    private let temporaryDirectory: AbsolutePath

    public init(
        temporaryDirectory: AbsolutePath
    ) {
        self.temporaryDirectory = temporaryDirectory
    }

    public func map(workspace: WorkspaceWithProjects) throws -> (WorkspaceWithProjects, [SideEffectDescriptor]) {
        var workspace = workspace
        workspace.workspace.path = temporaryDirectory
        return (
            workspace,
            [
                .directory(
                    DirectoryDescriptor(
                        path: temporaryDirectory,
                        state: .present
                    )
                ),
            ]
        )
    }
}
