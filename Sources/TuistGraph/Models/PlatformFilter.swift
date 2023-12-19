import Foundation

/// Convenience typealias to be used to ensure unique filters are applied
public typealias PlatformFilters = Set<PlatformFilter>

extension PlatformFilters: Comparable {
    public static func < (lhs: Set<Element>, rhs: Set<Element>) -> Bool {
        lhs.map(\.xcodeprojValue).sorted().joined() < rhs.map(\.xcodeprojValue).sorted().joined()
    }
}

/// Defines a set of platforms that can be used to limit where things
/// like build files, resources, and dependencies are used.
/// Context: https://github.com/tuist/tuist/pull/3152
public enum PlatformFilter: Comparable, Hashable, Codable, CaseIterable {
    case ios
    case macos
    case tvos
    case catalyst
    case driverkit
    case watchos
    case visionos

    public var xcodeprojValue: String {
        switch self {
        case .catalyst:
            return "maccatalyst"
        case .macos:
            return "macos"
        case .tvos:
            return "tvos"
        case .ios:
            return "ios"
        case .driverkit:
            return "driverkit"
        case .watchos:
            return "watchos"
        case .visionos:
            return "xros"
        }
    }

    /// It returns the platform that the filter is filtering for
    public var platform: Platform? {
        switch self {
        case .ios, .catalyst:
            return .iOS
        case .macos:
            return .macOS
        case .tvos:
            return .tvOS
        case .watchos:
            return .watchOS
        case .visionos:
            return .visionOS
        case .driverkit:
            // TODO: Add support for it
            return nil
        }
    }
}

extension PlatformFilters {
    /// Examples -
    /// This should not be here but downstream
    ///  `platformFilter = ios`
    ///  `platformFilters = (ios, xros, )`
    public var xcodeprojValue: [String] {
        map(\.xcodeprojValue).sorted()
    }
}
