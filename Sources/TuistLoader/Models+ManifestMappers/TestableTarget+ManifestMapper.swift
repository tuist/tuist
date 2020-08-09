import Foundation
import ProjectDescription
import TSCBasic
import TuistCore

extension TuistCore.TestableTarget {
    /// Maps a ProjectDescription.TestableTarget instance into a TuistCore.TestableTarget instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of testable target model.
    ///   - generatorPaths: Generator paths.
    static func from(manifest: ProjectDescription.TestableTarget,
                     generatorPaths: GeneratorPaths) throws -> TuistCore.TestableTarget
    {
        TestableTarget(target: TuistCore.TargetReference(projectPath: try generatorPaths.resolveSchemeActionProjectPath(manifest.target.projectPath),
                                                         name: manifest.target.targetName),
                       skipped: manifest.isSkipped,
                       parallelizable: manifest.isParallelizable,
                       randomExecutionOrdering: manifest.isRandomExecutionOrdering)
    }
}
