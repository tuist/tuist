import Foundation
import TuistCore
import TuistSupport

/// Tuist Workspace Markdown render Mapper.
///
/// A mapper that includes a .xcodesample.plist file within the generated xcworkspace directory.
/// This is used to render markdown inside the de workspace.
final class TuistWorkspaceRenderMarkdownReadmeMapper: WorkspaceMapping {
    func map(workspace: WorkspaceWithProjects) throws -> (WorkspaceWithProjects, [SideEffectDescriptor]) {
        guard workspace.workspace.generationOptions.renderMarkdownReadme else {
            return (workspace, [])
        }

        let tuistGeneratedFileDescriptor = FileDescriptor(
            path: workspace
                .workspace
                .xcWorkspacePath
                .appending(
                    component: ".xcodesamplecode.plist"
                ),
            contents: try PropertyListEncoder().encode([String]())
        )

        return (workspace, [
            .file(tuistGeneratedFileDescriptor),
        ])
    }
}
