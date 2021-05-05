import Foundation
import TSCBasic

public struct Cache: Equatable, Hashable {
    // Warning ⚠️
    //
    // If new property is added to a caching profile,
    // it must be added to `CacheProfileContentHasher` too.
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
    public let path: AbsolutePath?

    public init(profiles: [Profile], path: AbsolutePath?) {
        self.profiles = profiles
        self.path = path
    }

    public static let `default` = Cache(profiles: [Profile(name: "Development", configuration: "Debug")], path: nil)
}
