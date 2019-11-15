import Foundation

public enum Platform: String {
    case iOS = "ios"
    case macOS = "macos"
    case tvOS = "tvos"
    case watchOS = "watchos"

    public var caseValue: String {
        switch self {
        case .iOS: return "iOS"
        case .macOS: return "macOS"
        case .tvOS: return "tvOS"
        case .watchOS: return "watchOS"
        }
    }
}

extension Platform {
    public var xcodeSdkRoot: String {
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

    public var xcodeSupportedPlatforms: String {
        switch self {
        case .tvOS:
            return "appletvsimulator appletvos"
        case .iOS:
            return "iphonesimulator iphoneos"
        case .macOS:
            return "macosx"
        case .watchOS:
            return "watchsimulator watchos"
        }
    }

    /// The SDK Root Path within Xcode's developer directory
    public var xcodeSdkRootPath: String {
        switch self {
        case .iOS:
            return "Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk"
        case .macOS:
            return "Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
        case .tvOS:
            return "Platforms/AppleTVOS.platform/Developer/SDKs/AppleTVOS.sdk"
        case .watchOS:
            return "Platforms/WatchOS.platform/Developer/SDKs/WatchOS.sdk"
        }
    }
}
