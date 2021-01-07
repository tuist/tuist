import Foundation

// TODO: Add documentation
// TODO: Add unit tests
public struct Cache: Codable, Equatable {
    public struct Flavor: Codable, Equatable {
        public let name: String
        public let configuration: String

        public static func flavor(name: String, configuration: String) -> Flavor {
            return Flavor(name: name, configuration: configuration)
        }
    }

    public let flavors: [Flavor]

    public static func cache(flavors: [Flavor]) -> Cache {
        return Cache(flavors: flavors)
    }
}
