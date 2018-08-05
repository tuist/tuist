import Basic
import Foundation
import TuistCore
import xcodeproj

protocol WorkspaceGenerating: AnyObject {
    func generate(path: AbsolutePath,
                  context: GeneratorContexting,
                  options: GenerationOptions,
                  system: Systeming) throws
}

final class WorkspaceGenerator: WorkspaceGenerating {

    // MARK: - Attributes

    let projectGenerator: ProjectGenerating

    // MARK: - Init

    init(projectGenerator: ProjectGenerating = ProjectGenerator()) {
        self.projectGenerator = projectGenerator
    }

    // MARK: - WorkspaceGenerating

    func generate(path: AbsolutePath,
                  context: GeneratorContexting,
                  options: GenerationOptions,
                  system: Systeming = System()) throws {
        let workspaceName = "\(context.graph.name).xcworkspace"
        context.printer.print(section: "Generating workspace \(workspaceName)")
        let workspacePath = path.appending(component: workspaceName)
        let workspaceData = XCWorkspaceData(children: [])
        let workspace = XCWorkspace(data: workspaceData)
        try context.graph.projects.forEach { project in
            let xcodeprojPath = try projectGenerator.generate(project: project,
                                                              sourceRootPath: nil,
                                                              context: context,
                                                              options: options,
                                                              system: system)
            let relativePath = xcodeprojPath.relative(to: path)
            let location = XCWorkspaceDataElementLocationType.group(relativePath.asString)
            let fileRef = XCWorkspaceDataFileRef(location: location)
            workspace.data.children.append(XCWorkspaceDataElement.file(fileRef))
        }
        try workspace.write(path: workspacePath, override: true)
    }
}
