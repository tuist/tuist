import Basic
import Foundation
import ProjectDescription
import TuistCore
import TuistSupport

extension TuistCore.Product: ModelConvertible {
    init(manifest: ProjectDescription.Product, generatorPaths _: GeneratorPaths) throws {
        switch manifest {
        case .app:
            self = .app
        case .staticLibrary:
            self = .staticLibrary
        case .dynamicLibrary:
            self = .dynamicLibrary
        case .framework:
            self = .framework
        case .staticFramework:
            self = .staticFramework
        case .unitTests:
            self = .unitTests
        case .uiTests:
            self = .uiTests
        case .bundle:
            self = .bundle
        case .appExtension:
            self = .appExtension
        case .stickerPackExtension:
            self = .stickerPackExtension
        case .watch2App:
            self = .watch2App
        case .watch2Extension:
            self = .watch2Extension
        }
    }
}
