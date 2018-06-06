import Foundation

/// Target platform.
///
/// - ios: iOS.
/// - macos: macOS.
/// - watchos: watchOS.
/// - tvos: tvOS.
enum Platform: String {
    case ios
    case macos
    case watchos
    case tvos
}

// MARK: - Platform extension.

extension Platform {
    /// Returns Xcode SDKROOT value.
    var xcodeSdkRoot: String {
        switch self {
        case .macos:
            return "macosx"
        case .ios:
            return "iphoneos"
        case .tvos:
            return "appletvos"
        case .watchos:
            return "watchos"
        }
    }

    /// Returns Xcode SUPPORTED_PLATFORMS value.
    var xcodeSupportedPlatforms: String {
        switch self {
        case .tvos:
            return "appletvsimulator appletvos"
        case .watchos:
            return "watchsimulator watchos"
        case .ios:
            return "iphonesimulator iphoneos"
        case .macos:
            return "macosx"
        }
    }
}
