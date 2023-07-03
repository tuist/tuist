import Foundation

public typealias Destinations = Set<Destination>

/// A supported platform representation.
public enum Destination: String, Codable, Equatable, CaseIterable {
    case iPhone
    case iPad
    case mac
    case macWithiPadDesign
    case macCatalyst
    case appleWatch
    case appleTv
    
    var platform: Platform {
        switch self {
        case .iPad, .iPhone, .macWithiPadDesign:
            return .iOS
        case .mac, .macCatalyst:
            return .macOS
        case .appleTv:
            return .tvOS
        case .appleWatch:
            return .watchOS
        }
    }
}


extension Collection where Element == Destination {
    public func supports(_ platform: Platform) -> Bool {
        return self.contains(where: { $0.platform == platform })
    }
}
