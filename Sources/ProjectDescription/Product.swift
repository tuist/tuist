import Foundation

/// Possible products types.
public enum Product: String, Codable, Equatable {
    /// An application.
    case app
    /// A static library.
    case staticLibrary = "static_library"
    /// A dynamic library.
    case dynamicLibrary = "dynamic_library"
    /// A dynamic framework.
    case framework
    /// A static framework.
    case staticFramework
    /// A unit tests bundle.
    case unitTests = "unit_tests"
    /// A UI tests bundle.
    case uiTests = "ui_tests"
    /// A custom bundle. (currently only iOS resource bundles are supported).
    case bundle
    /// A command line tool (macOS platform only).
    case commandLineTool
    /// An appClip. (iOS platform only).
    case appClip
    /// An application extension.
    case appExtension = "app_extension"
    /// A Watch application. (watchOS platform only) .
    case watch2App
    /// A Watch application extension. (watchOS platform only).
    case watch2Extension
    /// A TV Top Shelf Extension.
    case tvTopShelfExtension
    /// An iMessage extension. (iOS platform only)
    case messagesExtension
    /// A sticker pack extension.
    case stickerPackExtension = "sticker_pack_extension"
    //    case watchApp
    //    case watchExtension
    //    case tvIntentsExtension
    //    case messagesApplication
    /// An XPC. (macOS platform only).
    case xpc
}
