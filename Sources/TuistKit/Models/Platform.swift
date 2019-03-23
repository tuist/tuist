import Foundation

enum Platform: String {
    case iOS = "ios"
    case macOS = "macos"
//    case watchOS = "watchos"
    case tvOS = "tvos"

    var caseValue: String {
        switch self {
        case .iOS: return "iOS"
        case .macOS: return "macOS"
        //        case .watchOS: return "watchOS"
        case .tvOS: return "tvOS"
        }
    }
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
//        case .watchOS:
//            return "watchos"
        }
    }

    var xcodeSupportedPlatforms: String {
        switch self {
        case .tvOS:
            return "appletvsimulator appletvos"
        //        case .watchOS:
        //            return "watchsimulator watchos"
        case .iOS:
            return "iphonesimulator iphoneos"
        case .macOS:
            return "macosx"
        }
    }
}

extension Platform {
    /**
     Not all platforms support launch screens.
     This check will `return true` if the platform supports launch screen storyboards.
     */
    var supportsLaunchScreen: Bool {
        switch self {
        case .iOS:
            return true
        default:
            return false
        }
    }
}
