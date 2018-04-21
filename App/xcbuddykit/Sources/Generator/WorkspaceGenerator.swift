import Basic
import Foundation
import PathKit
import xcproj

protocol WorkspaceGenerating: AnyObject {
    func generate(path: AbsolutePath,
                  generatorContext: GeneratorContexting) throws
}

final class WorkspaceGenerator: WorkspaceGenerating {
    let projectGenerator: ProjectGenerating

    init(projectGenerator: ProjectGenerating) {
        self.projectGenerator = projectGenerator
    }

    func generate(path: AbsolutePath,
                  generatorContext _: GeneratorContexting) throws {
        let workspacePath = Path(path.appending(component: Constants.Xcode.workspaceName).asString)
        let workspaceData = XCWorkspaceData(children: [])
        let workspace = XCWorkspace(data: workspaceData)

        try workspace.write(path: workspacePath, override: true)
    }
}
