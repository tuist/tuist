import Foundation

// TODO: Add documentation
// TODO: Add unit tests
public struct Cache: Codable, Equatable {
    public struct Flavor: Codable, Equatable {
        public let name: String
        public let configuration: String

        public static func flavor(name: String, configuration: String) -> Flavor {
            Flavor(name: name, configuration: configuration)
        }
    }

    public let flavors: [Flavor]

    public static func cache(flavors: [Flavor]) -> Cache {
        Cache(flavors: flavors)
    }
}
