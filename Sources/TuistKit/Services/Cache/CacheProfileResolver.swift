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
    public static let defaultCacheProfileFromTuist = TuistGraph.Cache.default.profiles[0]

    func resolveCacheProfile(
        named profileName: String?,
        from config: Config
    ) throws -> TuistGraph.Cache.Profile {
        if
            let name = profileName,
            let profiles = config.cache?.profiles
        {
            guard let profile = profiles.first(where: { $0.name == name }) else {
                // The name of the profile has not been found.
                throw CacheProfileResolverError.missingProfile(name: name, availableProfiles: profiles.map(\.name))
            }

            logger.notice(
                "Resolved cache profile '\(profile)'",
                metadata: .section
            )
            return profile // The profile selected from Config
        } else {
            if let defaultProfile = config.cache?.profiles.first {
                // The name of the profile was not passed &&
                // the list of profiles in Config file exists.
                logger.notice(
                    "Resolved default cache profile '\(defaultProfile)' from project's configuration file",
                    metadata: .section
                )
                return defaultProfile // The default profile selected from Config
            } else {
                // The name of the profile was not passed &&
                // the list of profiles in Config file is empty.
                let profile = CacheProfileResolver.defaultCacheProfileFromTuist
                logger.notice(
                    "Resolved cache profile '\(profile)' from Tuist's defaults",
                    metadata: .section
                )
                return profile // The default profile selected from Tuist's defaults
            }
        }
    }
}
