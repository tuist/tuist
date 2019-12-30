import Basic
import Foundation
import ProjectDescription
import TuistCore

extension TuistCore.ExecutionAction: ModelConvertible {
    init(manifest: ProjectDescription.ExecutionAction, generatorPaths: GeneratorPaths) throws {
        let targetReference: TuistCore.TargetReference? = try manifest.target.map { target in
            .project(path: try generatorPaths.resolve(projectPath: target.projectPath), target: target.targetName)
        }
        self.init(title: manifest.title, scriptText: manifest.scriptText, target: targetReference)
    }
}
