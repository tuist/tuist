import Foundation
import ProjectDescription
import TuistCore
import XcodeProjectGenerator

extension XcodeProjectGenerator.BuildConfiguration {
    /// Maps a ProjectDescription.Configuration instance into a XcodeProjectGenerator.BuildConfiguration instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of build configuration model.
    ///   - generatorPaths: Generator paths.
    static func from(manifest: ProjectDescription.Configuration) -> XcodeProjectGenerator.BuildConfiguration {
        let variant: XcodeProjectGenerator.BuildConfiguration.Variant
        switch manifest.variant {
        case .debug:
            variant = .debug
        case .release:
            variant = .release
        }
        return XcodeProjectGenerator.BuildConfiguration(name: manifest.name.rawValue, variant: variant)
    }
}
