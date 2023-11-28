import Foundation

// Set of deployment destinstions
public typealias Destinations = Set<Destination>

// Convenience collections of desitions mapped to platforms terminology.
extension Destinations {
    public static var watchOS: Destinations = [.appleWatch]
    // Currently we omit `.visionOSwithiPadDesign` from our default because `visionOS` is unreleased.
    public static var iOS: Destinations = [.iPhone, .iPad, .macWithiPadDesign]
    public static var macOS: Destinations = [.mac]
    public static var tvOS: Destinations = [.appleTv]
    public static var visionOS: Destinations = [.appleVision]
}

extension Destinations {
    // Convience set of platforms that are supported by a set of destinations
    public var platforms: Set<Platform> {
        let platforms = map(\.platform)
        return Set<Platform>(platforms)
    }
}

/// A supported deployment destination representation.
public enum Destination: String, Codable, Equatable, CaseIterable {
    // iPhone support
    case iPhone
    // iPad support
    case iPad
    // Native macOS support
    case mac
    // macOS support using iPad design
    case macWithiPadDesign
    // mac Catalyst support
    case macCatalyst
    // watchOS support
    case appleWatch
    // tvOS support
    case appleTv
    // visionOS support
    case appleVision
    // visionOS support useing iPad design
    case appleVisionWithiPadDesign

    // SDK Platform of a destination
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
