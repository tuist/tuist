import Foundation

public struct Cache: Equatable, Hashable {
    public struct Profile: Equatable, Hashable, CustomStringConvertible {
        public let name: String
        public let configuration: String

        public init(name: String, configuration: String) {
            self.name = name
            self.configuration = configuration
        }

        public var description: String {
            name
        }
    }

    public let profiles: [Profile]

    public init(profiles: [Profile]) {
        self.profiles = profiles
    }

    public static let `default` = Cache(profiles: [Profile(name: "development", configuration: "Debug")])
}
