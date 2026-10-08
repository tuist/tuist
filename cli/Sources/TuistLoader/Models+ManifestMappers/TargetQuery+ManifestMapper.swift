import Foundation
import ProjectDescription
import TuistCore
import XcodeGraph

extension XcodeGraph.TargetQuery {
    /// Maps a ProjectDescription.TargetQuery instance into a XcodeGraph.TargetQuery instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of a target query.
    static func from(manifest: ProjectDescription.TargetQuery) -> XcodeGraph.TargetQuery {
        switch manifest {
        case let .named(name): .named(name)
        case let .tagged(tag): .tagged(tag)
        case let .matching(pattern): .matching(pattern: pattern)
        }
    }
}

extension XcodeGraph.TestableTargetQuery {
    /// Maps a ProjectDescription.TestableTargetQuery instance into a XcodeGraph.TestableTargetQuery instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of a testable target query.
    ///   - generatorPaths: Generator paths.
    static func from(
        manifest: ProjectDescription.TestableTargetQuery,
        generatorPaths: GeneratorPaths
    ) throws -> XcodeGraph.TestableTargetQuery {
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

        let parallelization: XcodeGraph.TestableTarget.Parallelization = switch manifest.parallelization {
        case .disabled: .none
        case .swiftTestingOnly: .swiftTestingOnly
        case .enabled: .all
        }

        return TestableTargetQuery(
            query: .from(manifest: manifest.query),
            skipped: manifest.isSkipped,
            parallelization: parallelization,
            randomExecutionOrdering: manifest.isRandomExecutionOrdering,
            simulatedLocation: simulatedLocation
        )
    }
}
