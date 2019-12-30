import Basic
import Foundation
import ProjectDescription
import TuistCore

extension TuistCore.ExecutionAction: ModelConvertible {
    init(manifest: ProjectDescription.ExecutionAction, generatorPaths: GeneratorPaths) throws {
        let targetReference: TuistCore.TargetReference? = try manifest.target.map { target in
            let path: AbsolutePath
            if let projectPath = target.projectPath {
                path = try generatorPaths.resolve(path: projectPath)
            } else {
                path = generatorPaths.manifestDirectory
            }
            return .project(path: path, target: target.targetName)
        }
        self.init(title: manifest.title, scriptText: manifest.scriptText, target: targetReference)
    }
}
