import XcodeGraph

extension PlatformFilter {
    /// Initializes a `PlatformFilter` from a string that matches Xcodeproj values.
    init?(rawValue: String) {
        switch rawValue {
        case PlatformFilter.ios.xcodeprojValue:
            self = .ios
        case PlatformFilter.macos.xcodeprojValue:
            self = .macos
        case PlatformFilter.tvos.xcodeprojValue:
            self = .tvos
        case PlatformFilter.catalyst.xcodeprojValue:
            self = .catalyst
        case PlatformFilter.driverkit.xcodeprojValue:
            self = .driverkit
        case PlatformFilter.watchos.xcodeprojValue:
            self = .watchos
        case PlatformFilter.visionos.xcodeprojValue:
            self = .visionos
        default:
            return nil
        }
    }
}
