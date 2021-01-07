import Foundation

public struct Cache: Equatable, Hashable {
    public struct Flavor: Equatable, Hashable {
        public let name: String
        public let configuration: String

        public init(name: String, configuration: String) {
            self.name = name
            self.configuration = configuration
        }
    }

    public let flavors: [Flavor]

    public init(flavors: [Flavor]) {
        self.flavors = flavors
    }

    public static let `default` = Cache(flavors: [Flavor(name: "development", configuration: "Debug")])
}
