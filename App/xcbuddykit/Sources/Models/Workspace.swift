import Basic
import Foundation

/// Workspace that references other projects.
class Workspace: Equatable {
    /// Workspace name.
    let name: String

    /// Worskpace projects.
    let projects: [AbsolutePath]

    /// Initializes the Workspace with its attributes.
    ///
    /// - Parameter name: workspace name.
    /// - Parameter projects: paths to the projects.
    init(name: String, projects: [AbsolutePath]) {
        self.name = name
        self.projects = projects
    }

    /// Parses the workspace from its Swift manifest, Workspace.swift
    ///
    /// - Parameters:
    ///   - path: path to the folder where the Workspace.swift file is.
    ///   - context: graph loader context.
    /// - Returns: initialized Workspace.
    /// - Throws: an error if the workspace cannot be parsed
    static func at(_ path: AbsolutePath, context: GraphLoaderContexting) throws -> Workspace {
        let workspacePath = path.appending(component: Constants.Manifest.workspace)
        if !context.fileHandler.exists(workspacePath) { throw GraphLoadingError.missingFile(workspacePath) }
        let json = try context.manifestLoader.load(path: workspacePath, context: context)
        let projectsStrings: [String] = try json.get("projects")
        let name: String = try json.get("name")
        let projectsRelativePaths: [RelativePath] = projectsStrings.map({ RelativePath($0) })
        let projects = projectsRelativePaths.map({ path.appending($0) })
        return Workspace(name: name, projects: projects)
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
