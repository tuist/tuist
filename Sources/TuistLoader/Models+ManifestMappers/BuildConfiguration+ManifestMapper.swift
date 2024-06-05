import Foundation
import ProjectDescription
import TuistCore
import XcodeGraph

extension XcodeGraph.BuildConfiguration {
    /// Maps a ProjectDescription.Configuration instance into a XcodeGraph.BuildConfiguration instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of build configuration model.
    ///   - generatorPaths: Generator paths.
    static func from(manifest: ProjectDescription.Configuration) -> XcodeGraph.BuildConfiguration {
        let variant: XcodeGraph.BuildConfiguration.Variant
        switch manifest.variant {
        case .debug:
            variant = .debug
        case .release:
            variant = .release
        }
        return XcodeGraph.BuildConfiguration(name: manifest.name.rawValue, variant: variant)
    }
}
