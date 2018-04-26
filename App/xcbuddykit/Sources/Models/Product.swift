import Foundation

/// Product type.
///
/// - app: application.
/// - staticLibrary: static library.
/// - dynamicLibrary: dynamic library.
/// - framework: framework.
/// - unitTests: unit tests.
/// - uiTests: ui tests.
/// - appExtension: application extension.
/// - watchApp: watchOS 1 application.
/// - watch2App: watchOS version >= 2 application.
/// - watchExtension: watchOS 1 extension.
/// - watch2Extension: watchOS version >=2 extension.
/// - tvExtension: tvOS extension
/// - messagesApplication: iMessage application.
/// - messagesExtension: iMessage extension.
/// - stickerPack: Stickers pack.
public enum Product: String {
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
}

extension Product {
    /// Returns the Xcode value.
    var xcodeValue: String {
        switch self {
        case .app:
            return "com.apple.product-type.application"
        case .staticLibrary:
            return "com.apple.product-type.library.static"
        case .dynamicLibrary:
            return "com.apple.product-type.library.dynamic"
        case .framework:
            return "com.apple.product-type.framework"
        case .unitTests:
            return "com.apple.product-type.bundle.unit-test"
        case .uiTests:
            return "com.apple.product-type.bundle.ui-testing"
        case .appExtension:
            return "com.apple.product-type.app-extension"
        case .watchApp:
            return "com.apple.product-type.application.watchapp"
        case .watch2App:
            return "com.apple.product-type.application.watchapp2"
        case .watchExtension:
            return "com.apple.product-type.watchkit-extension"
        case .watch2Extension:
            return "com.apple.product-type.watchkit2-extension"
        case .tvExtension:
            return "com.apple.product-type.tv-app-extension"
        case .messagesApplication:
            return "com.apple.product-type.application.messages"
        case .messagesExtension:
            return "com.apple.product-type.app-extension.messages"
        case .stickerPack:
            return "com.apple.product-type.app-extension.messages-sticker-pack"
        }
    }
}
