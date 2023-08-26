import Foundation

public typealias Destinations = Set<Destination>

extension Destinations {
    public static var watchOS: Destinations = [.appleWatch]
    public static var iOS: Destinations = [.iPhone, .iPad, .macWithiPadDesign]
    public static var macOS: Destinations = [.mac]
    public static var tvOS: Destinations = [.appleTv]
    public static var visionOS: Destinations = [.appleVision]
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
}
