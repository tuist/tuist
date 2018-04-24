import Basic
import Foundation
import PathKit
import xcproj

/// Workspace generation protocol.
protocol WorkspaceGenerating: AnyObject {
    /// Generates the workspace at the given path.
    ///
    /// - Parameters:
    ///   - path: path where the workspace should be generated.
    ///   - context: generator context.
    /// - Throws: throw an error if the generation fails.
    func generate(path: AbsolutePath,
                  context: GeneratorContexting) throws
}

/// Workspace generator.
final class WorkspaceGenerator: WorkspaceGenerating {
    let projectGenerator: ProjectGenerating

    init(projectGenerator: ProjectGenerating = ProjectGenerator()) {
        self.projectGenerator = projectGenerator
    }

    func generate(path: AbsolutePath,
                  context: GeneratorContexting) throws {
        let workspaceName = "\(context.graph.name).xcworkspace"
        let workspacePath = Path(path.appending(component: workspaceName).asString)
        let workspaceData = XCWorkspaceData(children: [])
        let workspace = XCWorkspace(data: workspaceData)
        try context.graph.projects.forEach { project in
            let xcodeprojPath = try projectGenerator.generate(project: project, context: context)
            let relativePath = xcodeprojPath.relative(to: path)
            let location = XCWorkspaceDataElementLocationType.group(relativePath.asString)
            let fileRef = XCWorkspaceDataFileRef(location: location)
            workspace.data.children.append(XCWorkspaceDataElement.file(fileRef))
        }
        try workspace.write(path: workspacePath, override: true)
    }
}
