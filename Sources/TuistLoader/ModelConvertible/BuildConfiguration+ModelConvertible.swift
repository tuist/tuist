import Basic
import Foundation
import ProjectDescription
import TuistCore

extension TuistCore.BuildConfiguration: ModelConvertible {
    init(manifest: ProjectDescription.CustomConfiguration, generatorPaths _: GeneratorPaths) throws {
        let variant: TuistCore.BuildConfiguration.Variant
        switch manifest.variant {
        case .debug:
            variant = .debug
        case .release:
            variant = .release
        }
        self.init(name: manifest.name, variant: variant)
    }
}
