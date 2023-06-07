import Foundation
import TuistGraph
import XcodeProj

extension Product {
    public var xcodeValue: PBXProductType {
        switch self {
        case .app:
            return .application
        case .staticLibrary:
            return .staticLibrary
        case .dynamicLibrary:
            return .dynamicLibrary
        case .framework:
            return .framework
        case .staticFramework:
            return .framework
        case .unitTests:
            return .unitTestBundle
        case .uiTests:
            return .uiTestBundle
        case .bundle:
            return .bundle
        case .appExtension:
            return .appExtension
        //        case .watchApp:
        //            return .watchApp
        case .watch2App:
            return .watch2App
        //        case .watchExtension:
        //            return .watchExtension
        case .watch2Extension:
            return .watch2Extension
        case .tvTopShelfExtension: // Important Note: https://github.com/tuist/XcodeProj/pull/609
            return .appExtension
        // case .tvIntentsExtension: // Important Note: https://github.com/tuist/XcodeProj/pull/609
        //    return .tvExtension
        //        case .messagesApplication:
        //            return .messagesApplication
        case .messagesExtension:
            return .messagesExtension
        case .stickerPackExtension:
            return .stickerPack
        case .commandLineTool:
            return .commandLineTool
        case .appClip:
            return .onDemandInstallCapableApplication
        case .xpc:
            return .xpcService
        case .systemExtension:
            return .systemExtension
        case .extensionKitExtension:
            return .extensionKitExtension
        }
    }
}
