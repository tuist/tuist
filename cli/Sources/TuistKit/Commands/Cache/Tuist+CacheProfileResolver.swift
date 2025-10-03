import Foundation
import Logging
import TuistCore

enum CacheProfileError: LocalizedError, Equatable {
    case profileNotFound(profile: String, available: [String])

    var errorDescription: String? {
        switch self {
        case let .profileNotFound(profile, available):
            let builtins = "only-external, all-possible, none"
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
        cacheProfile: String?
    ) throws -> TuistGeneratedProjectOptions.CacheProfile {
        if ignoreBinaryCache {
            Logger.current.debug("Using cache profile none")
            return .init(base: .none, targets: [])
        }

        if !includedTargets.isEmpty {
            Logger.current.debug("Using cache profile all-possible")
            return .init(base: .allPossible, targets: [])
        }

        let profiles = project.generatedProject?.cacheOptions.profiles

        if let cacheProfile {
            Logger.current.debug("Using cache profile \(cacheProfile)")
            return try resolveFromProfileType(.from(commandLineValue: cacheProfile), profiles: profiles)
        }

        // The default profile was already validated when loaded
        if let configDefault = profiles?.defaultProfile,
           let profile = try? resolveFromProfileType(configDefault, profiles: profiles)
        {
            Logger.current.debug("Using cache profile \(configDefault)")
            return profile
        }

        Logger.current.debug("Using cache profile only-external")
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
            throw CacheProfileError.profileNotFound(
                profile: name,
                available: profiles?.profileByName.map(\.key) ?? []
            )
        }
    }
}
