import Foundation
import TuistCore

enum CacheProfileError: Error, LocalizedError, Equatable {
    case profileNotFound(String)

    var errorDescription: String? {
        switch self {
        case let .profileNotFound(profile):
            return "Cache profile '\(profile)' not found. Available profiles: 'only-external', 'all-possible', 'none', or custom profiles defined in profiles."
        }
    }
}

extension Tuist {
    /// Resolve the effective cache profile based on CLI flags, target focus, config default, and system default.
    func resolveCacheProfile(
        ignoreBinaryCache: Bool,
        includedTargets: Set<TargetQuery>,
        cacheProfile: String?
    ) throws -> TuistGeneratedProjectOptions.CacheProfile {
        if ignoreBinaryCache {
            return .init(base: .none, targets: [])
        }

        if !includedTargets.isEmpty {
            return .init(base: .allPossible, targets: [])
        }

        let profiles = project.generatedProject?.cacheOptions.profiles
        if let cacheProfile {
            return try resolveFromProfileType(
                .from(commandLineValue: cacheProfile),
                profiles: profiles
            )
        }

        if let configDefault = profiles?.defaultProfile {
            return try resolveFromProfileType(configDefault, profiles: profiles)
        }

        return .init(base: .onlyExternal, targets: [])
    }

    private func resolveFromProfileType(
        _ profile: TuistGeneratedProjectOptions.CacheProfileType,
        profiles: TuistGeneratedProjectOptions.CacheProfiles?
    ) throws -> TuistGeneratedProjectOptions.CacheProfile {
        switch profile {
        case .onlyExternal:
            return .init(base: .onlyExternal, targets: [])
        case .allPossible:
            return .init(base: .allPossible, targets: [])
        case .none:
            return .init(base: .none, targets: [])
        case let .custom(name):
            if let custom = profiles?.profileByName[name] {
                return custom
            }
            throw CacheProfileError.profileNotFound(name)
        }
    }
}
