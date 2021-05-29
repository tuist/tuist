import Foundation

/// It represents a cache configuration.
public struct Cache: Codable, Equatable {
    /// It represents a cache profile.
    public struct Profile: Codable, Equatable {
        /// The unique name of a profile
        public let name: String

        /// The configuration to be used when building the project during a caching warmup
        public let configuration: String

        /// Returns a `Cache.Profile` instance.
        ///
        /// - Parameters:
        ///     - name: The unique name of the cache profile
        ///     - configuration: The configuration to be used when building the project during a caching warmup
        /// - Returns: The `Cache.Profile` instance
        public static func profile(name: String, configuration: String) -> Profile {
            Profile(name: name, configuration: configuration)
        }
    }

    /// A list of the cache profiles.
    public let profiles: [Profile]
    /// The path where the cache will be stored, if `nil` it will be a default location in a shared directory.
    public let path: Path?

    /// Returns a `Cache` instance containing the given profiles.
    /// If no profile list is provided, tuist's default profile will be taken as the default.
    /// If no profile is provided in `tuist cache --profile` command, the first profile from the profiles list will be taken as the default.
    /// - Parameters:
    ///   - profiles: Profiles to be chosen from
    ///   - path: The path where the cache will be stored, if `nil` it will be a default location in a shared directory.
    /// - Returns: The `Cache` instance
    public static func cache(profiles: [Profile] = [], path: Path? = nil) -> Cache {
        Cache(profiles: profiles, path: path)
    }
}
