import Foundation
import xcodeproj

public enum Product: String, CustomStringConvertible {
    case app
    case staticLibrary = "static_library"
    case dynamicLibrary = "dynamic_library"
    case framework
    case unitTests = "unit_tests"
    case uiTests = "ui_tests"
    case appExtension = "app_extension"
    case watchApp = "watch_app"
    case watch2App = "watch_2_app"
    case watchExtension = "watch_extension"
    case watch2Extension = "watch_2_extension"
    case tvExtension = "tv_extension"
    case messagesApplication = "messages_application"
    case messagesExtension = "messages_extension"
    case stickerPack = "sticker_pack"

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
        case .unitTests:
            return "unitTests"
        case .uiTests:
            return "uiTests"
        case .appExtension:
            return "appExtension"
        case .watchApp:
            return "watchApp"
        case .watch2App:
            return "watch2App"
        case .watchExtension:
            return "watchExtension"
        case .watch2Extension:
            return "watch2Extension"
        case .tvExtension:
            return "tvExtension"
        case .messagesApplication:
            return "messagesApplication"
        case .messagesExtension:
            return "messagesExtension"
        case .stickerPack:
            return "stickerPack"
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
        case .unitTests:
            return "unit tests"
        case .uiTests:
            return "ui tests"
        case .appExtension:
            return "app extension"
        case .watchApp:
            return "watch application"
        case .watch2App:
            return "watch 2 application"
        case .watchExtension:
            return "watch extension"
        case .watch2Extension:
            return "watch 2 extension"
        case .tvExtension:
            return "tv extension"
        case .messagesApplication:
            return "iMessage application"
        case .messagesExtension:
            return "iMessage extension"
        case .stickerPack:
            return "stickers pack"
        }
    }

    static func forPlatform(_ platform: Platform) -> Set<Product> {
        var base: [Product] = [
            .app,
            .staticLibrary,
            .dynamicLibrary,
            .framework,
        ]

        if platform == .iOS {
            base.append(.appExtension)
            base.append(.stickerPack)
            base.append(.messagesApplication)
            base.append(.messagesExtension)
        }

        if platform == .tvOS {
            base.append(.tvExtension)
        }

        if platform == .macOS ||
            platform == .tvOS ||
            platform == .iOS {
            base.append(.unitTests)
            base.append(.uiTests)
        }

        if platform == .watchOS {
            base.append(contentsOf: [
                .watchApp,
                .watch2App,
                .watchExtension,
                .watch2Extension,
            ])
        }
        return Set(base)
    }
}

extension Product {
    var xcodeValue: PBXProductType {
        switch self {
        case .app:
            return .application
        case .staticLibrary:
            return .staticLibrary
        case .dynamicLibrary:
            return .dynamicLibrary
        case .framework:
            return .framework
        case .unitTests:
            return .unitTestBundle
        case .uiTests:
            return .uiTestBundle
        case .appExtension:
            return .appExtension
        case .watchApp:
            return .watchApp
        case .watch2App:
            return .watch2App
        case .watchExtension:
            return .watchExtension
        case .watch2Extension:
            return .watch2Extension
        case .tvExtension:
            return .tvExtension
        case .messagesApplication:
            return .messagesApplication
        case .messagesExtension:
            return .messagesExtension
        case .stickerPack:
            return .stickerPack
        }
    }
}
