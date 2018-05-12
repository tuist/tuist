import Basic
import Foundation
import xcodeproj

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
    /// Project generator.
    let projectGenerator: ProjectGenerating

    /// Initializes the workspace generator with the project generator.
    ///
    /// - Parameter projectGenerator: project generator.
    init(projectGenerator: ProjectGenerating = ProjectGenerator()) {
        self.projectGenerator = projectGenerator
    }

    /// Generates the workspace at the given path.
    ///
    /// - Parameters:
    ///   - path: path where the workspace should be generated.
    ///   - context: generator context.
    /// - Throws: throw an error if the generation fails.
    func generate(path: AbsolutePath,
                  context: GeneratorContexting) throws {
        let workspaceName = "\(context.graph.name).xcworkspace"
        context.printer.print(section: "Generating workspace \(workspaceName)")
        let workspacePath = path.appending(component: workspaceName)
        let workspaceData = XCWorkspaceData(children: [])
        let workspace = XCWorkspace(data: workspaceData)
        try context.graph.projects.forEach { project in
            let xcodeprojPath = try projectGenerator.generate(project: project, sourceRootPath: nil, context: context)
            let relativePath = xcodeprojPath.relative(to: path)
            let location = XCWorkspaceDataElementLocationType.group(relativePath.asString)
            let fileRef = XCWorkspaceDataFileRef(location: location)
            workspace.data.children.append(XCWorkspaceDataElement.file(fileRef))
        }
        try workspace.write(path: workspacePath, override: true)
    }
}
