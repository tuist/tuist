import Basic
import Foundation
import TuistCore
import xcodeproj

protocol WorkspaceGenerating: AnyObject {
    @discardableResult
    func generate(path: AbsolutePath,
                  graph: Graphing,
                  options: GenerationOptions,
                  system: Systeming,
                  printer: Printing,
                  resourceLocator: ResourceLocating) throws -> AbsolutePath
}

final class WorkspaceGenerator: WorkspaceGenerating {
    // MARK: - Attributes

    let projectGenerator: ProjectGenerating

    // MARK: - Init

    init(projectGenerator: ProjectGenerating = ProjectGenerator()) {
        self.projectGenerator = projectGenerator
    }

    // MARK: - WorkspaceGenerating

    @discardableResult
    func generate(path: AbsolutePath,
                  graph: Graphing,
                  options: GenerationOptions,
                  system: Systeming = System(),
                  printer: Printing = Printer(),
                  resourceLocator: ResourceLocating = ResourceLocator()) throws -> AbsolutePath {
        let workspaceName = "\(graph.name).xcworkspace"
        printer.print(section: "Generating workspace \(workspaceName)")
        let workspacePath = path.appending(component: workspaceName)
        let workspaceData = XCWorkspaceData(children: [])
        let workspace = XCWorkspace(data: workspaceData)
        try graph.projects.forEach { project in
            let xcodeprojPath = try projectGenerator.generate(project: project,
                                                              options: options,
                                                              graph: graph,
                                                              sourceRootPath: nil,
                                                              system: system,
                                                              printer: printer,
                                                              resourceLocator: resourceLocator)

            let relativePath = xcodeprojPath.relative(to: path)
            let location = XCWorkspaceDataElementLocationType.group(relativePath.asString)
            let fileRef = XCWorkspaceDataFileRef(location: location)
            workspace.data.children.append(XCWorkspaceDataElement.file(fileRef))
        }
        try workspace.write(path: workspacePath, override: true)

        return workspacePath
    }
}
