import Foundation

// MARK: - Workspace

public struct Workspace: Codable, Equatable {
    /// Name of the workspace
    public let name: String

    /// List of project relative paths (or glob patterns) to generate and include
    public let projects: [Path]
    
    /// List of custom schemes
    public let schemes: [WorkspaceDescription.Scheme]

    /// List of files to include in the workspace (e.g. Documentation)
    public let additionalFiles: [FileElement]

    /// Workspace
    ///
    /// This can be used to customize the generated workspace.
    ///
    /// - Parameters:
    ///   - name: Name of the workspace.
    ///   - projects: List of project relative paths (or glob patterns) to generate and include.
    ///   - additionalFiles: List of files to include in the workspace (e.g. Documentation)
    public init(name: String, projects: [Path], schemes: [WorkspaceDescription.Scheme] = [], additionalFiles: [FileElement] = []) {
        self.name = name
        self.projects = projects
        self.schemes = schemes
        self.additionalFiles = additionalFiles
        dumpIfNeeded(self)
    }
}
