import Foundation
import TuistGraph
import TuistSupport

enum CacheProfileResolverError: FatalError, Equatable {
    case missingProfile(name: String, availableProfiles: [String])

    var description: String {
        switch self {
        case let .missingProfile(name, availableProfiles):
            return "The cache profile '\(name)' is missing in your project's configuration. Available cache profiles: \(availableProfiles.listed())."
        }
    }

    var type: ErrorType {
        switch self {
        case .missingProfile:
            return .abort
        }
    }
}

struct CacheProfileResolver {
    func resolveCacheProfile(
        named profileName: String?,
        from config: Config
    ) throws -> TuistGraph.Cache.Profile {
        let profiles: [Cache.Profile]
        let fromConfig: Bool
        if let cacheConfig = config.cache,
           !cacheConfig.profiles.isEmpty
        {
            fromConfig = true
            profiles = cacheConfig.profiles
        } else {
            fromConfig = false
            profiles = TuistGraph.Cache.default.profiles
        }
        if let name = profileName {
            guard let profile = profiles.first(where: { $0.name == name }) else {
                // The name of the profile has not been found.
                throw CacheProfileResolverError.missingProfile(name: name, availableProfiles: profiles.map(\.name))
            }

            logger.notice(
                "Resolved cache profile '\(profile)'",
                metadata: .section
            )
            return profile
        } else {
            let profile = profiles[0]
            logger.notice(
                "Resolved cache profile '\(profile)' from \(fromConfig ? "project's configuration file" : "Tuist's defaults")",
                metadata: .section
            )
            return profile
        }
    }
}
