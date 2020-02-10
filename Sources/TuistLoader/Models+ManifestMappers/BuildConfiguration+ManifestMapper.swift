import Foundation
import ProjectDescription
import TuistCore

extension TuistCore.BuildConfiguration {
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
