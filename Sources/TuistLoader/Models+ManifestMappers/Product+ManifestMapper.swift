import Foundation
import ProjectDescription
import TuistCore

extension TuistCore.Product {
    static func from(manifest: ProjectDescription.Product) -> TuistCore.Product {
        switch manifest {
        case .app:
            return .app
        case .staticLibrary:
            return .staticLibrary
        case .dynamicLibrary:
            return .dynamicLibrary
        case .framework:
            return .framework
        case .staticFramework:
            return .staticFramework
        case .unitTests:
            return .unitTests
        case .uiTests:
            return .uiTests
        case .bundle:
            return .bundle
        case .appExtension:
            return .appExtension
        case .stickerPackExtension:
            return .stickerPackExtension
        case .watch2App:
            return .watch2App
        case .watch2Extension:
            return .watch2Extension
        }
    }
}
