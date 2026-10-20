import XcodeGraph

/// A build destination represented by a slice in an XCFramework, rather than a workspace's consumers.
public enum BinaryCacheVariant: String, CaseIterable, Codable, Sendable {
    case iosDevice = "ios-device"
    case iosSimulator = "ios-simulator"
    case catalyst = "ios-maccatalyst"
    case macos = "macos-device"

    public var platform: Platform { self == .macos ? .macOS : .iOS }

    public var platformFilter: PlatformFilter {
        switch self {
        case .macos: .macos
        case .catalyst: .catalyst
        case .iosDevice, .iosSimulator: .ios
        }
    }

    public var architectures: Set<BinaryArchitecture> {
        switch self {
        case .iosDevice: [.arm64]
        case .iosSimulator, .catalyst, .macos: [.arm64, .x8664]
        }
    }

    public func matches(_ library: XCFrameworkInfoPlist.Library) -> Bool {
        switch self {
        case .iosDevice: library.platform == .iOS && library.platformVariant == nil
        case .iosSimulator: library.platform == .iOS && library.platformVariant == .simulator
        case .catalyst: library.platform == .iOS && library.platformVariant == .maccatalyst
        case .macos: library.platform == .macOS && library.platformVariant == nil
        }
    }
}
