import Basic
import Foundation
import ProjectDescription
import TuistCore

extension TuistCore.TestableTarget {
    static func from(manifest: ProjectDescription.TestableTarget,
                     generatorPaths: GeneratorPaths) throws -> TuistCore.TestableTarget {
        TestableTarget(target: TuistCore.TargetReference(projectPath: try generatorPaths.resolveSchemeActionProjectPath(manifest.target.projectPath),
                                                         name: manifest.target.targetName),
                       skipped: manifest.isSkipped,
                       parallelizable: manifest.isParallelizable,
                       randomExecutionOrdering: manifest.isRandomExecutionOrdering)
    }
}
