import Foundation

// MARK: - Product

public enum Product: String, Codable, Equatable {
    case app
    case staticLibrary = "static_library"
    case dynamicLibrary = "dynamic_library"
    case framework
    case staticFramework
    case unitTests = "unit_tests"
    case uiTests = "ui_tests"
    case bundle
    case appClips

    // Not supported yet
    case appExtension = "app_extension"
//    case watchApp
    case watch2App
//    case watchExtension
    case watch2Extension
//    case tvExtension
//    case messagesApplication
    case messagesExtension
    case stickerPackExtension = "sticker_pack_extension"
}
