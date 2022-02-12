import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistGraph

extension TuistGraph.TestableTarget {
    /// Maps a ProjectDescription.TestableTarget instance into a TuistGraph.TestableTarget instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of testable target model.
    ///   - generatorPaths: Generator paths.
    static func from(
        manifest: ProjectDescription.TestableTarget,
        generatorPaths: GeneratorPaths
    ) throws -> TuistGraph.TestableTarget {
        TestableTarget(
            target: TuistGraph.TargetReference(
                projectPath: try generatorPaths.resolveSchemeActionProjectPath(manifest.target.projectPath),
                name: manifest.target.targetName
            ),
            skipped: manifest.isSkipped,
            parallelizable: manifest.isParallelizable,
            randomExecutionOrdering: manifest.isRandomExecutionOrdering
        )
    }
}
