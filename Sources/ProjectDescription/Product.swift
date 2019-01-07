import Foundation

// MARK: - Product

public enum Product: String, Codable {
    case app
    case staticLibrary = "static_library"
    case dynamicLibrary = "dynamic_library"
    case framework
    case staticFramework
    case unitTests = "unit_tests"
    case uiTests = "ui_tests"

    // Not supported yet
//    case appExtension
//    case watchApp
//    case watch2App
//    case watchExtension
//    case watch2Extension
//    case tvExtension
//    case messagesApplication
//    case messagesExtension
//    case stickerPack
}
