import Basic
import Foundation
import ProjectDescription
import TuistCore

extension TuistCore.TestableTarget: ModelConvertible {
    init(manifest: ProjectDescription.TestableTarget, generatorPaths: GeneratorPaths) throws {
        let path = try generatorPaths.resolve(projectPath: manifest.target.projectPath)
        self.init(target: TuistCore.TargetReference(projectPath: path, name: manifest.target.targetName),
                  skipped: manifest.isSkipped,
                  parallelizable: manifest.isParallelizable,
                  randomExecutionOrdering: manifest.isRandomExecutionOrdering)
    }
}
