import Basic
import Foundation

protocol WorkspaceGenerating: AnyObject {
}

final class WorkspaceGenerator: WorkspaceGenerating {
    let projectGenerator: ProjectGenerating

    init(projectGenerator: ProjectGenerating) {
        self.projectGenerator = projectGenerator
    }

    func generate(path _: AbsolutePath) {
    }
}
