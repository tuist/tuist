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

        if let path = manifest.storeKitConfigurationPath {
            storeKitConfigurationPath = try generatorPaths.resolveSchemeActionProjectPath(path)
        }

        return TuistGraph.RunActionOptions(
            storeKitConfigurationPath: storeKitConfigurationPath
        )
    }
}
