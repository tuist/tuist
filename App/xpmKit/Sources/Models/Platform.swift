import Foundation

/// Target platform.
///
/// - ios: iOS.
/// - macos: macOS.
/// - watchos: watchOS.
/// - tvos: tvOS.
enum Platform: String {
    case iOS
    case macOS
    case watchOS
    case tvOS
}

// MARK: - Platform extension.

extension Platform {
    /// Returns Xcode SDKROOT value.
    var xcodeSdkRoot: String {
        switch self {
        case .macOS:
            return "macosx"
        case .iOS:
            return "iphoneos"
        case .tvOS:
            return "appletvos"
        case .watchOS:
            return "watchos"
        }
    }

    /// Returns Xcode SUPPORTED_PLATFORMS value.
    var xcodeSupportedPlatforms: String {
        switch self {
        case .tvOS:
            return "appletvsimulator appletvos"
        case .watchOS:
            return "watchsimulator watchos"
        case .iOS:
            return "iphonesimulator iphoneos"
        case .macOS:
            return "macosx"
        }
    }
}
