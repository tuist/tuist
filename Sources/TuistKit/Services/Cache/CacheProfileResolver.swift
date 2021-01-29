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
        if
            let name = profileName,
            let profiles = config.cache?.profiles {
            guard let profile = profiles.first(where: { $0.name == name }) else {
                // The name of the profile has not been found.
                return .notFound(profileName: name, availableProfiles: profiles.map(\.name))
            }
            return .selectedFromConfig(profile)
        } else {
            if let defaultProfile = config.cache?.profiles.first {
                // The name of the profile was not passed &&
                // the list of profiles in Config file exists.
                return .defaultFromConfig(defaultProfile)
            } else {
                // The name of the profile was not passed &&
                // the list of profiles in Config file is empty.
                return .defaultFromTuist(TuistGraph.Cache.default.profiles[0])
            }
        }
    }
}
