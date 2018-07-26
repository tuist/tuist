import Foundation

// MARK: - Product

public enum Product: String, Codable {
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
