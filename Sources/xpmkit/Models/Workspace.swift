import Basic
import Foundation
import xpmcore

class Workspace: Equatable {

    // MARK: - Attributes

    let name: String
    let projects: [AbsolutePath]

    // MARK: - Init

    init(name: String, projects: [AbsolutePath]) {
        self.name = name
        self.projects = projects
    }

    static func at(_ path: AbsolutePath,
                   fileHandler: FileHandling = FileHandler(),
                   manifestLoader: GraphManifestLoading = GraphManifestLoader()) throws -> Workspace {
        let workspacePath = path.appending(component: Constants.Manifest.workspace)
        if !fileHandler.exists(workspacePath) { throw GraphLoadingError.missingFile(workspacePath) }
        let json = try manifestLoader.load(path: workspacePath)

        let projectsStrings: [String] = try json.get("projects")
        let name: String = try json.get("name")
        let projectsRelativePaths: [RelativePath] = projectsStrings.map({ RelativePath($0) })
        let projects = projectsRelativePaths.map({ path.appending($0) })
        return Workspace(name: name, projects: projects)
    }

    // MARK: - Equatable

    static func == (lhs: Workspace, rhs: Workspace) -> Bool {
        return lhs.projects == rhs.projects
    }
}
