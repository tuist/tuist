import Foundation
import ProjectDescription
import TSCBasic
// import TuistCore
import TuistGraph

extension TuistGraph.RunActionOptions {
    /// Maps a ProjectDescription.RunActionOptions instance into a TuistGraph.RunActionOptions instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of the options.
    ///   - generatorPaths: Generator paths.
    static func from(manifest: ProjectDescription.RunActionOptions,
                     generatorPaths: GeneratorPaths) throws -> TuistGraph.RunActionOptions
    {
        var storeKitConfigurationPath: AbsolutePath?
        var simulatedLocation: SimulatedLocation?

        if let path = manifest.storeKitConfigurationPath {
            storeKitConfigurationPath = try generatorPaths.resolveSchemeActionProjectPath(path)
        }

        if let simulatedLocationManifest = manifest.simulatedLocation {
            switch simulatedLocationManifest {
            case let .custom(gpxFile):
                simulatedLocation = .gpxFile(try generatorPaths.resolveSchemeActionProjectPath(gpxFile))
            default:
                simulatedLocation = .reference(simulatedLocationManifest.identifier)
            }
        }

        return TuistGraph.RunActionOptions(
            storeKitConfigurationPath: storeKitConfigurationPath,
            simulatedLocation: simulatedLocation
        )
    }
}
