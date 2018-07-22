import Foundation
import xcodeproj

public enum Product: String, CustomStringConvertible {
    case app
    case staticLibrary
    case dynamicLibrary
    case framework
    case unitTests
    case uiTests
    case appExtension
    case watchApp
    case watch2App
    case watchExtension
    case watch2Extension
    case tvExtension
    case messagesApplication
    case messagesExtension
    case stickerPack

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
