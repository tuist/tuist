import Foundation
import XcodeProj

public enum Product: String, CustomStringConvertible, CaseIterable, Encodable {
    case app
    case staticLibrary = "static_library"
    case dynamicLibrary = "dynamic_library"
    case framework
    case staticFramework
    case unitTests = "unit_tests"
    case uiTests = "ui_tests"
    case bundle
    case appExtension = "app_extension"
    //    case watchApp = "watch_app"
    case watch2App = "watch_2_app"
    //    case watchExtension = "watch_extension"
    case watch2Extension = "watch_2_extension"
    //    case tvExtension = "tv_extension"
    //    case messagesApplication = "messages_application"
    case messagesExtension = "messages_extension"
    case stickerPackExtension = "sticker_pack_extension"
    case appClips

    public var caseValue: String {
        switch self {
        case .app:
            return "app"
        case .staticLibrary:
            return "staticLibrary"
        case .dynamicLibrary:
            return "dynamicLibrary"
        case .framework:
            return "framework"
        case .staticFramework:
            return "staticFramework"
        case .unitTests:
            return "unitTests"
        case .uiTests:
            return "uiTests"
        case .bundle:
            return "bundle"
        case .appExtension:
            return "appExtension"
        //        case .watchApp:
        //            return "watchApp"
        case .watch2App:
            return "watch2App"
        //        case .watchExtension:
        //            return "watchExtension"
        case .watch2Extension:
            return "watch2Extension"
        //        case .tvExtension:
        //            return "tvExtension"
        //        case .messagesApplication:
        //            return "messagesApplication"
        case .messagesExtension:
            return "messagesExtension"
        case .stickerPackExtension:
            return "stickerPackExtension"
        case .appClips:
            return "appClips"
        }
    }

    public var description: String {
        switch self {
        case .app:
            return "application"
        case .staticLibrary:
            return "static library"
        case .dynamicLibrary:
            return "dynamic library"
        case .framework:
            return "framework"
        case .staticFramework:
            return "staticFramework"
        case .unitTests:
            return "unit tests"
        case .uiTests:
            return "ui tests"
        case .bundle:
            return "bundle"
        case .appExtension:
            return "app extension"
        //        case .watchApp:
        //            return "watch application"
        case .watch2App:
            return "watch 2 application"
        //        case .watchExtension:
        //            return "watch extension"
        case .watch2Extension:
            return "watch 2 extension"
        //        case .tvExtension:
        //            return "tv extension"
        //        case .messagesApplication:
        //            return "iMessage application"
        case .messagesExtension:
            return "iMessage extension"
        case .stickerPackExtension:
            return "sticker pack extension"
        case .appClips:
            return "appClips"
        }
    }

    /// Returns true if the target can be ran.
    public var runnable: Bool {
        switch self {
        case .app:
            return true
        default:
            return false
        }
    }

    /// Returns true if the product is a tests bundle.
    public var testsBundle: Bool {
        self == .uiTests || self == .unitTests
    }

    public static func forPlatform(_ platform: Platform) -> Set<Product> {
        var base: [Product] = [
            .app,
            .staticLibrary,
            .dynamicLibrary,
            .framework,
        ]

        if platform == .iOS {
            base.append(.appExtension)
            base.append(.stickerPackExtension)
            //            base.append(.messagesApplication)
            base.append(.messagesExtension)
        }

        if platform == .tvOS {
            //            base.append(.tvExtension)
        }

        if platform == .macOS ||
            platform == .tvOS ||
            platform == .iOS
        {
            base.append(.unitTests)
            base.append(.uiTests)
        }

        //        if platform == .watchOS {
        //            base.append(contentsOf: [
        //                .watchApp,
        //                .watch2App,
        //                .watchExtension,
        //                .watch2Extension,
        //            ])
        //        }
        return Set(base)
    }

    public var isStatic: Bool {
        [.staticLibrary, .staticFramework].contains(self)
    }

    public var isFramework: Bool {
        [.framework, .staticFramework].contains(self)
    }

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
        //        case .tvExtension:
        //            return .tvExtension
        //        case .messagesApplication:
        //            return .messagesApplication
        case .messagesExtension:
            return .messagesExtension
        case .stickerPackExtension:
            return .stickerPack
        case .appClips:
          return .onDemandInstallCapableApplication
        }
    }
}
