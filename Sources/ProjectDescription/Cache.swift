import Foundation

// TODO: Add documentation
// TODO: Add unit tests
public struct Cache: Codable, Equatable {
    public struct Profile: Codable, Equatable {
        public let name: String
        public let configuration: String

        public static func profile(name: String, configuration: String) -> Profile {
            Profile(name: name, configuration: configuration)
        }
    }

    public let profiles: [Profile]

    public static func cache(profiles: [Profile]) -> Cache {
        Cache(profiles: profiles)
    }
}
