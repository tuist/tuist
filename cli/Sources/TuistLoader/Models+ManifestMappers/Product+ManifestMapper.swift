import Foundation
import ProjectDescription
import XcodeGraph

extension XcodeGraph.Product {
    static func from(manifest: ProjectDescription.Product) -> XcodeGraph.Product {
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
        case .tvTopShelfExtension:
            return .tvTopShelfExtension
        case .stickerPackExtension:
            return .stickerPackExtension
        case .watch2App:
            return .watch2App
        case .watch2Extension:
            return .watch2Extension
        case .messagesExtension:
            return .messagesExtension
        case .commandLineTool:
            return .commandLineTool
        case .appClip:
            return .appClip
        case .xpc:
            return .xpc
        case .systemExtension:
            return .systemExtension
        case .extensionKitExtension:
            return .extensionKitExtension
        case .macro:
            return .macro
        }
    }
}
