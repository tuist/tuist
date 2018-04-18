import Basic
import Foundation

class Workspace {
    var projects: [AbsolutePath]

    init(projects: [AbsolutePath]) {
        self.projects = projects
    }

    init(path: AbsolutePath, context: GraphLoaderContexting) throws {
        let workspacePath = path.appending(component: Constants.Manifest.workspace)
        if !context.fileHandler.exists(workspacePath) { throw GraphLoadingError.missingFile(workspacePath) }
        let json = try context.manifestLoader.load(path: workspacePath, context: context)
        let projectsStrings: [String] = try json.get("projects")
        let projectsRelativePaths: [RelativePath] = projectsStrings.map({ RelativePath($0) })
        projects = projectsRelativePaths.map({ path.appending($0) })
    }
}
