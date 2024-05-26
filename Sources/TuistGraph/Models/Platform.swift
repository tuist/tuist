import Foundation
import TuistSupport

struct UnsupportedPlatformError: FatalError, CustomStringConvertible, Equatable {
    let type: TuistSupport.ErrorType = .abort

    let input: String
    var description: String {
        "Specified platform \(input) does not map to any of these supported platforms: \(Platform.allCases.map(\.caseValue).joined(separator: ", ")) "
    }
}

public enum Platform: String, CaseIterable, Codable, Comparable {
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

    public init?(commandLineValue: String) {
        self.init(rawValue: commandLineValue.lowercased())
    }

    public static func from(commandLineValue: String) throws -> Platform {
        guard let platform = Platform(rawValue: commandLineValue.lowercased()) else {
            throw UnsupportedPlatformError(input: commandLineValue)
        }
        return platform
    }

    public static func < (lhs: Platform, rhs: Platform) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public enum PackagePlatform: String, CaseIterable, Codable, Comparable {
    case iOS = "ios"
    case macCatalyst = "maccatalyst"
    case macOS = "macos"
    case tvOS = "tvos"
    case watchOS = "watchos"
    case visionOS = "visionos"

    public var caseValue: String {
        switch self {
        case .iOS: return "iOS"
        case .macCatalyst: return "macCatalyst"
        case .macOS: return "macOS"
        case .tvOS: return "tvOS"
        case .watchOS: return "watchOS"
        case .visionOS: return "visionOS"
        }
    }

    public static func < (lhs: PackagePlatform, rhs: PackagePlatform) -> Bool {
        lhs.rawValue < rhs.rawValue
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
}
