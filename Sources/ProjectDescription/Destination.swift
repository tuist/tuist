import Foundation

/// Set of deployment destinations
public typealias Destinations = Set<Destination>

/// Convenience collections of destinations mapped to platforms terminology.
extension Destinations {
    public static let watchOS: Destinations = [.appleWatch]
    /// Currently we omit `.visionOSwithiPadDesign` from our default because `visionOS` is unreleased.
    public static let iOS: Destinations = [.iPhone, .iPad, .macWithiPadDesign]
    public static let macOS: Destinations = [.mac]
    public static let tvOS: Destinations = [.appleTv]
    public static let visionOS: Destinations = [.appleVision]
}

extension Destinations {
    /// Convenience set of platforms that are supported by a set of destinations
    public var platforms: Set<Platform> {
        let platforms = map(\.platform)
        return Set<Platform>(platforms)
    }
}

/// A supported deployment destination representation.
public enum Destination: String, Codable, Equatable, CaseIterable, Sendable {
    /// iPhone support
    case iPhone
    /// iPad support
    case iPad
    /// Native macOS support
    case mac
    /// macOS support using iPad design
    case macWithiPadDesign
    /// mac Catalyst support
    case macCatalyst
    /// watchOS support
    case appleWatch
    /// tvOS support
    case appleTv
    /// visionOS support
    case appleVision
    /// visionOS support using iPad design
    case appleVisionWithiPadDesign

    /// SDK Platform of a destination
    public var platform: Platform {
        switch self {
        case .iPad, .iPhone, .macCatalyst, .macWithiPadDesign, .appleVisionWithiPadDesign:
            return .iOS
        case .mac:
            return .macOS
        case .appleTv:
            return .tvOS
        case .appleWatch:
            return .watchOS
        case .appleVision:
            return .visionOS
        }
    }
}
