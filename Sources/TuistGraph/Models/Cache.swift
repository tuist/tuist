import Foundation
import TSCBasic
import struct TSCUtility.Version

public struct Cache: Equatable, Hashable {
    // Warning ⚠️
    //
    // If new property is added to a caching profile,
    // it must be added to `CacheProfileContentHasher` too.
    public struct Profile: Equatable, Hashable, CustomStringConvertible {
        public let name: String
        public let configuration: String
        public let device: String?
        public let os: Version?

        public init(
            name: String,
            configuration: String,
            device: String? = nil,
            os: Version? = nil
        ) {
            self.name = name
            self.configuration = configuration
            self.device = device
            self.os = os
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

    public static let `default` = Cache(
        profiles: [
            Profile(name: "Development", configuration: "Debug"),
            Profile(name: "Release", configuration: "Release"),
        ],
        path: nil
    )
}
