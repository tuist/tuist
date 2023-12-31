import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport

extension TuistGraph.Dependencies {
    /// Maps a ProjectDescription.Dependencies instance into a TuistGraph.Dependencies instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of dependencies.
    ///   - generatorPaths: Generator paths.
    static func from(
        manifest: ProjectDescription.Dependencies,
        generatorPaths: GeneratorPaths
    ) throws -> Self {
        let swiftPackageManager: TuistGraph.SwiftPackageManagerDependencies? = try {
            guard let swiftPackageManager = manifest.swiftPackageManager else {
                return nil
            }
            return try TuistGraph.SwiftPackageManagerDependencies.from(
                manifest: swiftPackageManager,
                generatorPaths: generatorPaths
            )
        }()
        let platforms = try manifest.platforms.map { try TuistGraph.PackagePlatform.from(manifest: $0) }

        return Self(
            swiftPackageManager: swiftPackageManager,
            platforms: Set(platforms)
        )
    }
}
