import Foundation
import xcodeproj

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
