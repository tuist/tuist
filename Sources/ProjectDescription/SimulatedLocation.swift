import Foundation

/// Simulated location represents a GPS location that is used when running an app on the simulator.
public struct SimulatedLocation: Codable, Equatable, Sendable {
    /// The identifier of the location (e.g. London, England)
    public var identifier: String?
    /// Path to a .gpx file that indicates the location
    public var gpxFile: Path?

    private init(
        identifier: String? = nil,
        gpxFile: Path? = nil
    ) {
        self.identifier = identifier
        self.gpxFile = gpxFile
    }

    public static func custom(gpxFile: Path) -> SimulatedLocation {
        .init(gpxFile: gpxFile)
    }

    public static var london: SimulatedLocation {
        .init(identifier: "London, England")
    }

    public static var johannesburg: SimulatedLocation {
        .init(identifier: "Johannesburg, South Africa")
    }

    public static var moscow: SimulatedLocation {
        .init(identifier: "Moscow, Russia")
    }

    public static var mumbai: SimulatedLocation {
        .init(identifier: "Mumbai, India")
    }

    public static var tokyo: SimulatedLocation {
        .init(identifier: "Tokyo, Japan")
    }

    public static var sydney: SimulatedLocation {
        .init(identifier: "Sydney, Australia")
    }

    public static var hongKong: SimulatedLocation {
        .init(identifier: "Hong Kong, China")
    }

    public static var honolulu: SimulatedLocation {
        .init(identifier: "Honolulu, HI, USA")
    }

    public static var sanFrancisco: SimulatedLocation {
        .init(identifier: "San Francisco, CA, USA")
    }

    public static var mexicoCity: SimulatedLocation {
        .init(identifier: "Mexico City, Mexico")
    }

    public static var newYork: SimulatedLocation {
        .init(identifier: "New York, NY, USA")
    }

    public static var rioDeJaneiro: SimulatedLocation {
        .init(identifier: "Rio de Janeiro, Brazil")
    }
}
