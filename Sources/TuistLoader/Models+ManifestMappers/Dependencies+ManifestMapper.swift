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
    public static func from(manifest: ProjectDescription.Dependencies, generatorPaths: GeneratorPaths) throws -> Self {
        let carthage: TuistGraph.CarthageDependencies? = try {
            guard let carthage = manifest.carthage else {
                return nil
            }
            return try TuistGraph.CarthageDependencies.from(manifest: carthage)
        }()
        let swiftPackageManager: TuistGraph.SwiftPackageManagerDependencies? = try {
            guard let swiftPackageManager = manifest.swiftPackageManager else {
                return nil
            }
            return try TuistGraph.SwiftPackageManagerDependencies.from(
                manifest: swiftPackageManager,
                generatorPaths: generatorPaths
            )
        }()
        let platforms = try manifest.platforms.map { try TuistGraph.Platform.from(manifest: $0) }

        return Self(
            carthage: carthage,
            swiftPackageManager: swiftPackageManager,
            platforms: Set(platforms)
        )
    }
}
