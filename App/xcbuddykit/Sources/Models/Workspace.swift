import Basic
import Foundation

/// Workspace that references other projects.
class Workspace: Equatable {
    /// Worskpace projects.
    var projects: [AbsolutePath]

    /// Initializes the Workspace with its attributes.
    ///
    /// - Parameter projects: paths to the projects.
    init(projects: [AbsolutePath]) {
        self.projects = projects
    }

    /// Parses the workspace from its Swift manifest, Workspace.swift
    ///
    /// - Parameters:
    ///   - path: path to the folder where the Workspace.swift file is.
    ///   - context: graph loader context.
    /// - Returns: initialized Workspace.
    /// - Throws: an error if the workspace cannot be parsed
    static func parse(from path: AbsolutePath, context: GraphLoaderContexting) throws -> Workspace {
        let workspacePath = path.appending(component: Constants.Manifest.workspace)
        if !context.fileHandler.exists(workspacePath) { throw GraphLoadingError.missingFile(workspacePath) }
        let json = try context.manifestLoader.load(path: workspacePath, context: context)
        let projectsStrings: [String] = try json.get("projects")
        let projectsRelativePaths: [RelativePath] = projectsStrings.map({ RelativePath($0) })
        let projects = projectsRelativePaths.map({ path.appending($0) })
        return Workspace(projects: projects)
    }

    /// Compares two workspaces.
    ///
    /// - Parameters:
    ///   - lhs: first workspace to be compared.
    ///   - rhs: second workspace to be compared.
    /// - Returns: true if the two workspaces are the same.
    static func == (lhs: Workspace, rhs: Workspace) -> Bool {
        return lhs.projects == rhs.projects
    }
}
