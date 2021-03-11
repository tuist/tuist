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
    static func from(manifest: ProjectDescription.Dependencies, generatorPaths: GeneratorPaths) throws -> Self {
        let carthage: TuistGraph.CarthageDependencies? = try {
            guard let carthage = manifest.carthage else {
                return nil
            }
            return try TuistGraph.CarthageDependencies.from(manifest: carthage)
        }()

        return Self(carthage: carthage)
    }
}
