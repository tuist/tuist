public enum CacheProfileType: Codable, Equatable, Sendable, Hashable {
    case onlyExternal
    case allPossible
    case none
    case custom(String)
}

extension CacheProfileType: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        switch BaseCacheProfile(rawValue: value) {
        case .onlyExternal:
            self = .onlyExternal
        case .allPossible:
            self = .allPossible
        case .none?:
            self = .none
        case nil:
            self = .custom(value)
        }
    }
}

public enum BaseCacheProfile: String, Codable, Equatable, Sendable, Hashable, CaseIterable {
    case onlyExternal = "only-external"
    case allPossible = "all-possible"
    case none
}

public struct CacheProfile: Codable, Equatable, Sendable, Hashable {
    public let base: BaseCacheProfile
    public let targetQueries: [TargetQuery]
    public let exceptTargetQueries: [TargetQuery]

    public init(
        base: BaseCacheProfile,
        targetQueries: [TargetQuery],
        exceptTargetQueries: [TargetQuery] = []
    ) {
        self.base = base
        self.targetQueries = targetQueries
        self.exceptTargetQueries = exceptTargetQueries
    }

    public static let onlyExternal = CacheProfile(base: .onlyExternal, targetQueries: [], exceptTargetQueries: [])
    public static let allPossible = CacheProfile(base: .allPossible, targetQueries: [], exceptTargetQueries: [])
    public static let none = CacheProfile(base: .none, targetQueries: [], exceptTargetQueries: [])
}

public struct CacheProfiles: Codable, Equatable, Sendable, Hashable {
    public let profileByName: [String: CacheProfile]
    public let defaultProfile: CacheProfileType

    public init(
        _ profileByName: [String: CacheProfile],
        default defaultProfile: CacheProfileType
    ) {
        self.profileByName = profileByName
        self.defaultProfile = defaultProfile
    }
}

public struct CacheOptions: Codable, Equatable, Sendable, Hashable {
    public var keepSourceTargets: Bool
    public var profiles: CacheProfiles

    public init(
        keepSourceTargets: Bool,
        profiles: CacheProfiles
    ) {
        self.keepSourceTargets = keepSourceTargets
        self.profiles = profiles
    }
}

#if DEBUG
    extension CacheOptions {
        public static func test(
            keepSourceTargets: Bool = false,
            profiles: CacheProfiles = .init([:], default: .onlyExternal)
        ) -> Self {
            .init(
                keepSourceTargets: keepSourceTargets,
                profiles: profiles
            )
        }
    }
#endif
