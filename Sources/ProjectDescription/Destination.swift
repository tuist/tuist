import Foundation

public typealias Destinations = Set<Destination>

extension Destinations {
    public static var watchOS: Destinations = [.appleWatch]
    public static var iOS: Destinations = [.iPhone, .iPad, .macWithiPadDesign]
    public static var macOS: Destinations = [.mac]
    public static var tvOS: Destinations = [.appleTv]
    public static var visionOS: Destinations = [.appleVision]
}

extension Destinations {
    public var platforms: Set<Platform> {
        let platforms = map(\.platform)
        return Set<Platform>(platforms)
    }
}

/// A supported platform representation.
public enum Destination: String, Codable, Equatable, CaseIterable {
    case iPhone
    case iPad
    case mac
    case macWithiPadDesign
    case macCatalyst
    case appleWatch
    case appleTv
    case appleVision
    case appleVisionWithiPadDesign

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
