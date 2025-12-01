import ProjectDescription
import TuistCore
import TuistSupport

enum CacheOptionsManifestMapperError: FatalError, Equatable {
    /// Thrown when the default cache profile references a non-existent profile name.
    case defaultCacheProfileNotFound(profile: String, available: [String])
    /// Thrown when a custom profile name collides with a built-in profile name.
    case reservedProfileName(profile: String)

    /// Error type.
    var type: ErrorType {
        switch self {
        case .defaultCacheProfileNotFound: return .abort
        case .reservedProfileName: return .abort
        }
    }

    /// Error description.
    var description: String {
        switch self {
        case let .defaultCacheProfileNotFound(profile, available):
            let builtins = BaseCacheProfile.allCases.map { ".\($0)" }.joined(separator: ", ")
            if available.isEmpty {
                return "Default cache profile '\(profile)' not found. Available profiles: \(builtins)."
            } else {
                let custom = available.sorted().joined(separator: ", ")
                return "Default cache profile '\(profile)' not found. Available profiles: \(builtins), or custom profiles: \(custom)."
            }
        case let .reservedProfileName(profile):
            let reserved = BaseCacheProfile.allCases.map(\.rawValue).joined(separator: ", ")
            return "Custom profile name '\(profile)' is reserved. The following names cannot be used: \(reserved)."
        }
    }
}

extension TuistCore.CacheOptions {
    static func from(
        manifest: ProjectDescription.Config.CacheOptions
    ) throws -> Self {
        let profiles = TuistCore.CacheProfiles.from(manifest: manifest.profiles)

        // Validate that custom profile names don't use reserved built-in names
        let reservedNames = Set(BaseCacheProfile.allCases.map(\.rawValue))
        for profileName in profiles.profileByName.keys where reservedNames.contains(profileName) {
            throw CacheOptionsManifestMapperError.reservedProfileName(profile: profileName)
        }

        // Validate that default profile exists if it's a custom profile
        if case let .custom(name) = profiles.defaultProfile, profiles.profileByName[name] == nil {
            throw CacheOptionsManifestMapperError.defaultCacheProfileNotFound(
                profile: name,
                available: Array(profiles.profileByName.keys)
            )
        }

        return .init(
            keepSourceTargets: manifest.keepSourceTargets,
            profiles: profiles
        )
    }
}

extension TuistCore.CacheProfiles {
    static func from(
        manifest: ProjectDescription.CacheProfiles
    ) -> Self {
        .init(
            manifest.profileByName.mapValues { .from(manifest: $0) },
            default: .from(manifest: manifest.defaultProfile)
        )
    }
}

extension TuistCore.CacheProfile {
    static func from(
        manifest: ProjectDescription.CacheProfile
    ) -> Self {
        .init(
            base: .from(manifest: manifest.base),
            targetQueries: manifest.targetQueries.map { .from(manifest: $0) }
        )
    }
}

extension TuistCore.BaseCacheProfile {
    static func from(
        manifest: ProjectDescription.BaseCacheProfile
    ) -> Self {
        switch manifest {
        case .onlyExternal: return .onlyExternal
        case .allPossible: return .allPossible
        case .none: return .none
        }
    }
}

extension TuistCore.CacheProfileType {
    static func from(
        manifest: ProjectDescription.CacheProfileType
    ) -> Self {
        switch manifest {
        case .onlyExternal: return .onlyExternal
        case .allPossible: return .allPossible
        case .none: return .none
        case let .custom(name): return .custom(name)
        }
    }
}

extension TuistCore.TargetQuery {
    static func from(
        manifest: ProjectDescription.TargetQuery
    ) -> Self {
        switch manifest {
        case let .named(name): return .named(name)
        case let .tagged(tag): return .tagged(tag)
        }
    }
}
