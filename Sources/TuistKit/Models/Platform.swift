import Foundation

enum Platform: String {
    case iOS
    case macOS
    case watchOS
    case tvOS
}

extension Platform {
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
