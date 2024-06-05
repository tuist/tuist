import Foundation
import TSCBasic

public enum SimulatedLocation {
    case gpxFile(AbsolutePath)
    case reference(String)

    /// A unique identifier string for the selected simulated location.
    ///
    /// In case of Xcode's simulated locations, this is a string representing the location.
    /// In case of a custom GPX file, this is a path to that file.
    public var identifier: String {
        switch self {
        case let .gpxFile(path):
            return path.pathString
        case let .reference(identifier):
            return identifier
        }
    }

    /// A reference type is 1 if using Xcode's built-in simulated locations.
    /// Otherwise, it is 0.
    public var referenceType: String {
        if case .gpxFile = self { return "0" }
        return "1"
    }
}

extension SimulatedLocation: Equatable, Codable, Hashable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)

        guard value.hasSuffix(".gpx") else {
            self = .reference(value)
            return
        }

        self = .gpxFile(try AbsolutePath(validating: value))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(identifier)
    }
}
