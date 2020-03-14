import Foundation

public enum Platform: String, CaseIterable {
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

    /// Returns whether the platform has simulators.
    public var hasSimulators: Bool {
        switch self {
        case .macOS: return false
        default: return true
        }
    }

    /// It returns the destination that should be used to
    /// compile a product for this platform's simulator.
    public var xcodeSimulatorDestination: String? {
        switch self {
        case .macOS: return nil
        default: return "platform=\(caseValue) Simulator"
        }
    }

    /// Returns the SDK of the platform's simulator
    /// If the platform doesn't have simulators, like macOS, it returns nil.
    public var xcodeSimulatorSDK: String? {
        switch self {
        case .tvOS: return "appletvsimulator"
        case .iOS: return "iphonesimulator"
        case .watchOS: return "watchsimulator"
        case .macOS: return nil
        }
    }

    /// Returns the SDK to build for the platform's device.
    public var xcodeDeviceSDK: String {
        switch self {
        case .tvOS:
            return "appletvos"
        case .iOS:
            return "iphoneos"
        case .macOS:
            return "macosx"
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

    public var xcodeDeveloperSdkRootPath: String? {
        switch self {
        case .iOS:
            return "Platforms/iPhoneOS.platform/Developer/Library"
        case .macOS:
            return "Platforms/MacOSX.platform/Developer/Library"
        default: return nil
        }
    }
}
