import Foundation

/// A cache configuration.
public struct Cache: Codable, Equatable {
    /// A cache profile.
    public struct Profile: Codable, Equatable {
        /// The unique name of a profile
        public var name: String

        /// The configuration to be used when building the project during a caching warmup
        public var configuration: String

        /// The device to be used when building the project during a caching warmup
        public var device: String? = nil

        /// The version of the OS to be used when building the project during a caching warmup
        public var os: String? = nil
    }

    /// A list of the cache profiles.
    public var profiles: [Profile] = []
    /// The path where the cache will be stored, if `nil` it will be a default location in a shared directory.
    public var path: Path? = nil
}
