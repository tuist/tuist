import Foundation

public enum Platform: String, CaseIterable, Codable {
    case iOS = "ios"
    case macOS = "macos"
    case tvOS = "tvos"
    case watchOS = "watchos"
    case visionOS = "visionos"

    public var caseValue: String {
        switch self {
        case .iOS: return "iOS"
        case .macOS: return "macOS"
        case .tvOS: return "tvOS"
        case .watchOS: return "watchOS"
        case .visionOS: return "visionOS"
        }
    }

    /// A dictionary that contains the oldest supported version of each platform
    public static func oldestVersions(isLegacy: Bool) -> [Platform: String] {
        guard !isLegacy else {
            /// https://github.com/apple/swift-package-manager/blob/5d3db35d1f388f4b0bb7e82f4cfa050103bb3e07/Sources/PackageModel/Platform.swift#L32-L42
            return [
                .iOS: "9.0",
                .tvOS: "9.0",
                .macOS: "10.10",
                .watchOS: "2.0",
                .visionOS: "1.0",
            ]
        }

        /// https://github.com/apple/swift-package-manager/blob/86b245fd68157a0592b1d9ef15284e3b22c3fb44/Sources/PackageModel/Platform.swift#L34-L44
        return [
            .iOS: "11.0",
            .tvOS: "11.0",
            .macOS: "10.13",
            .watchOS: "4.0",
            .visionOS: "1.0",
        ]
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
        case .visionOS:
            return "xros"
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
        case .visionOS: return "xrsimulator"
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
        case .visionOS:
            return "xros"
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
        case .visionOS:
            return "Platforms/XROS.platform/Developer/SDKs/XROS.sdk"
        }
    }

    public var xcodeDeveloperSdkRootPath: String {
        switch self {
        case .iOS:
            return "Platforms/iPhoneOS.platform/Developer/Library"
        case .macOS:
            return "Platforms/MacOSX.platform/Developer/Library"
        case .tvOS:
            return "Platforms/AppleTVOS.platform/Developer/Library"
        case .watchOS:
            return "Platforms/WatchOS.platform/Developer/Library"
        case .visionOS:
            return "Platforms/XROS.platform/Developer/Library"
        }
    }

    /// Returns the directory name whose Carthage uses to save frameworks.
    public var carthageDirectory: String {
        switch self {
        case .iOS, .watchOS, .tvOS, .visionOS:
            return caseValue
        case .macOS:
            return "Mac"
        }
    }
}
