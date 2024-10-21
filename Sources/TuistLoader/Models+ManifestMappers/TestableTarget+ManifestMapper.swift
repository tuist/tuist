import Foundation
import Path
import ProjectDescription
import TuistCore
import XcodeGraph

extension XcodeGraph.TestableTarget {
    /// Maps a ProjectDescription.TestableTarget instance into a XcodeGraph.TestableTarget instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of testable target model.
    ///   - generatorPaths: Generator paths.
    static func from(
        manifest: ProjectDescription.TestableTarget,
        generatorPaths: GeneratorPaths
    ) throws -> XcodeGraph.TestableTarget {
        let target = XcodeGraph.TargetReference(
            projectPath: try generatorPaths.resolveSchemeActionProjectPath(manifest.target.projectPath),
            name: manifest.target.targetName
        )

        var simulatedLocation: XcodeGraph.SimulatedLocation?

        if let manifestLocation = manifest.simulatedLocation {
            switch (manifestLocation.identifier, manifestLocation.gpxFile) {
            case let (identifier?, .none):
                simulatedLocation = .reference(identifier)
            case let (.none, gpxFile?):
                simulatedLocation = .gpxFile(try generatorPaths.resolveSchemeActionProjectPath(gpxFile))
            default:
                break
            }
        }

        return TestableTarget(
            target: target,
            skipped: manifest.isSkipped,
            parallelizable: manifest.isParallelizable,
            randomExecutionOrdering: manifest.isRandomExecutionOrdering,
            simulatedLocation: simulatedLocation
        )
    }
}
