import Basic
import Foundation
import ProjectDescription
import TuistCore

extension TuistCore.Platform: ModelConvertible {
    init(manifest: ProjectDescription.Platform, generatorPaths _: GeneratorPaths) throws {
        switch manifest {
        case .macOS:
            self = .macOS
        case .iOS:
            self = .iOS
        case .tvOS:
            self = .tvOS
        case .watchOS:
            self = .watchOS
        }
    }
}
