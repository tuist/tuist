import Foundation
import Unbox

public enum Product: String, UnboxableEnum {
    case app
    case module
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
    var xcodeValue: String {
        switch self {
        case .app:
            return "com.apple.product-type.application"
        case .module:
            return "io.xcbuddy.product-type.module"
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
