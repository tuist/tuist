import Foundation
import ProjectDescription
import TuistCore

extension TuistCore.BuildConfiguration {
    /// Maps a ProjectDescription.BuildConfiguration instance into a TuistCore.BuildConfiguration instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of build configuration model.
    ///   - generatorPaths: Generator paths.
    static func from(manifest: ProjectDescription.CustomConfiguration) -> TuistCore.BuildConfiguration {
        let variant: TuistCore.BuildConfiguration.Variant
        switch manifest.variant {
        case .debug:
            variant = .debug
        case .release:
            variant = .release
        }
        return TuistCore.BuildConfiguration(name: manifest.name, variant: variant)
    }
}
