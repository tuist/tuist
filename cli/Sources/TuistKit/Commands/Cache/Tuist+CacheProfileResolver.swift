import Foundation
import Logging
import TuistConfig
import TuistCore

enum CacheProfileError: LocalizedError, Equatable {
    case profileNotFound(profile: String, available: [String])

    var errorDescription: String? {
        switch self {
        case let .profileNotFound(profile, available):
            let builtins = BaseCacheProfile.allCases.map(\.rawValue).joined(separator: ", ")
            if available.isEmpty {
                return "Cache profile '\(profile)' not found. Available profiles: \(builtins), or custom profiles defined in profiles."
            } else {
                let custom = available.sorted().joined(separator: ", ")
                return "Cache profile '\(profile)' not found. Available profiles: \(builtins), or custom profiles: \(custom)."
            }
        }
    }
}

extension Tuist {
    /// Resolve the effective cache profile based on CLI flags, target focus, config default, and system default.
    func resolveCacheProfile(
        ignoreBinaryCache: Bool,
        includedTargets: Set<TargetQuery>,
        cacheProfile: CacheProfileType?
    ) throws -> CacheProfile {
        if ignoreBinaryCache {
            Logger.current.debug("Using cache profile none")
            return .none
        }

        if case .some(.none) = cacheProfile {
            Logger.current.debug("Using cache profile none")
            return .none
        }

        let profiles = project.generatedProject?.cacheOptions.profiles
        let contextualCommandDefault: CacheProfile = includedTargets.isEmpty ? .onlyExternal : .allPossible
        let resolvedCommandDefault: CacheProfile
        if let configDefault = profiles?.defaultProfile {
            resolvedCommandDefault = try resolveFromProfileType(
                configDefault,
                profiles: profiles,
                commandDefault: contextualCommandDefault
            )
        } else {
            resolvedCommandDefault = contextualCommandDefault
        }

        if let cacheProfile {
            Logger.current.debug("Using cache profile \(cacheProfile)")
            return try resolveFromProfileType(
                cacheProfile,
                profiles: profiles,
                commandDefault: resolvedCommandDefault
            )
        }

        if let configDefault = profiles?.defaultProfile {
            Logger.current.debug("Using cache profile \(configDefault)")
            return resolvedCommandDefault
        }

        Logger.current.debug("Using cache profile \(contextualCommandDefault.base)")
        return contextualCommandDefault
    }

    private func resolveFromProfileType(
        _ profile: CacheProfileType,
        profiles: CacheProfiles?,
        commandDefault: CacheProfile
    ) throws -> CacheProfile {
        switch profile {
        case .onlyExternal:
            return .onlyExternal
        case .allPossible:
            return .allPossible
        case .none:
            return .none
        case let .custom(name):
            if let custom = profiles?.profileByName[name] {
                return resolveCustomProfile(custom, commandDefault: commandDefault)
            }
            throw CacheProfileError.profileNotFound(
                profile: name,
                available: profiles?.profileByName.map(\.key) ?? []
            )
        }
    }

    private func resolveCustomProfile(
        _ profile: CacheProfile,
        commandDefault: CacheProfile
    ) -> CacheProfile {
        let baseProfile: CacheProfile
        switch profile.base {
        case .onlyExternal:
            baseProfile = .onlyExternal
        case .allPossible:
            baseProfile = .allPossible
        case .commandDefault:
            baseProfile = commandDefault
        case .none:
            baseProfile = .none
        }

        return CacheProfile(
            base: baseProfile.base,
            targetQueries: baseProfile.targetQueries + profile.targetQueries,
            exceptTargetQueries: baseProfile.exceptTargetQueries + profile.exceptTargetQueries
        )
    }
}
