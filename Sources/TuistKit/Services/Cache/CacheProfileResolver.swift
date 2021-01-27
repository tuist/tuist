import Foundation
import TuistGraph

struct CacheProfileResolver {
    enum ResolvedCacheProfile: Equatable {
        case defaultFromTuist(TuistGraph.Cache.Profile)
        case defaultFromConfig(TuistGraph.Cache.Profile)
        case selectedFromConfig(TuistGraph.Cache.Profile)
        case notFound(profileName: String, availableProfiles: [String])
    }

    func resolveCacheProfile(
        named profileName: String?,
        from config: Config
    ) -> ResolvedCacheProfile {
        // The name of the profile was not passed &&
        // the list of profiles in Config file exists.
        if
            case .none = profileName,
            let cacheConfig = config.cache,
            let defaultProfile = cacheConfig.profiles.first {
            return .defaultFromConfig(defaultProfile)
        }

        // The name of the profile was not passed &&
        // the list of profiles in Config file is empty.
        guard
            let name = profileName,
            let cacheConfig = config.cache,
            !cacheConfig.profiles.isEmpty
        else {
            return .defaultFromTuist(TuistGraph.Cache.default.profiles[0])
        }

        let profiles = cacheConfig.profiles
        guard let profile = profiles.first(where: { $0.name == name }) else {
            // The name of the profile has not been found.
            return .notFound(profileName: name, availableProfiles: profiles.map(\.name))
        }
        return .selectedFromConfig(profile)
    }
}
