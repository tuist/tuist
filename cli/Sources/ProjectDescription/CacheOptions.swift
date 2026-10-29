extension Tuist {
    /// Represents a cache storage backend.
    public enum CacheStorageOption: Codable, Equatable, Sendable {
        /// Store and fetch cached binaries on the local machine.
        case local
        /// Store and fetch cached binaries from the remote Tuist server.
        case remote
    }

    /// Options for caching.
    public struct CacheOptions: Codable, Equatable, Sendable {
        public var keepSourceTargets: Bool
        public var profiles: CacheProfiles
        /// The storage backends to use for caching. Defaults to `[.local, .remote]`.
        public var storages: [CacheStorageOption]
        /// Whether cached binaries carry the debug information LLDB needs to step into their sources.
        /// Defaults to `true`.
        ///
        /// When `false`, Debug binaries are built without dSYMs or source metadata, which makes `tuist cache`
        /// faster and needs much less disk, and `tuist generate` uses them without verifying their debug
        /// information. Breakpoints in cached modules then don't resolve to their sources. Binaries warmed with
        /// one setting are never used by a project with the other.
        public var debugSymbols: Bool

        public static func options(
            keepSourceTargets: Bool = false,
            profiles: CacheProfiles = [:],
            storages: [CacheStorageOption] = [.local, .remote],
            debugSymbols: Bool = true
        ) -> Self {
            self.init(
                keepSourceTargets: keepSourceTargets,
                profiles: profiles,
                storages: storages,
                debugSymbols: debugSymbols
            )
        }
    }
}

extension Tuist.CacheOptions {
    /// A manifest encoded before `debugSymbols` existed decodes with debug symbols on.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            keepSourceTargets: try container.decode(Bool.self, forKey: .keepSourceTargets),
            profiles: try container.decode(CacheProfiles.self, forKey: .profiles),
            storages: try container.decode([Tuist.CacheStorageOption].self, forKey: .storages),
            debugSymbols: try container.decodeIfPresent(Bool.self, forKey: .debugSymbols) ?? true
        )
    }
}
