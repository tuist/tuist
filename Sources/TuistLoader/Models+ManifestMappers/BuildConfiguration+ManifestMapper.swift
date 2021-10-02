import Foundation
import ProjectDescription
import TuistCore
import TuistGraph

extension TuistGraph.BuildConfiguration {
    /// Maps a ProjectDescription.Configuration instance into a TuistGraph.BuildConfiguration instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of build configuration model.
    ///   - generatorPaths: Generator paths.
    static func from(manifest: ProjectDescription.Configuration) -> TuistGraph.BuildConfiguration {
        let variant: TuistGraph.BuildConfiguration.Variant
        switch manifest.variant {
        case .debug:
            variant = .debug
        case .release:
            variant = .release
        }
        return TuistGraph.BuildConfiguration(name: manifest.name.rawValue, variant: variant)
    }
}
