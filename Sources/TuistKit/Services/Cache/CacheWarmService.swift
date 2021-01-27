import Foundation
import TSCBasic
import TuistCache
import TuistCore
import TuistGraph
import TuistLoader
import TuistSupport

enum CacheWarmServiceError: FatalError, Equatable {
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

final class CacheWarmService {
    /// Generator Model Loader, used for getting the user config
    private let generatorModelLoader: GeneratorModelLoader

    init(manifestLoader: ManifestLoader = ManifestLoader(),
         manifestLinter: ManifestLinter = ManifestLinter())
    {
        generatorModelLoader = GeneratorModelLoader(manifestLoader: manifestLoader,
                                                    manifestLinter: manifestLinter)
    }

    func run(path: String?, profile: String?, xcframeworks: Bool) throws {
        let path = self.path(path)
        let config = try generatorModelLoader.loadConfig(at: currentPath)
        let cache = Cache(storageProvider: CacheStorageProvider(config: config))
        let cacheControllerFactory = CacheControllerFactory(cache: cache)
        let contentHasher = CacheContentHasher()
        let cacheController: CacheControlling
        if xcframeworks {
            cacheController = cacheControllerFactory.makeForXCFramework(contentHasher: contentHasher)
        } else {
            cacheController = cacheControllerFactory.makeForSimulatorFramework(contentHasher: contentHasher)
        }
        let profile = try cacheProfile(named: profile, from: config)
        try cacheController.cache(path: path, configuration: profile.configuration)
    }

    // MARK: - Helpers

    private func path(_ path: String?) -> AbsolutePath {
        if let path = path {
            return AbsolutePath(path, relativeTo: currentPath)
        } else {
            return currentPath
        }
    }

    private func cacheProfile(named profileName: String?, from config: Config) throws -> TuistGraph.Cache.Profile {
        let resolvedCacheProfile = CacheProfileResolver().resolveCacheProfile(
            named: profileName,
            from: config
        )

        switch resolvedCacheProfile {
            case let .defaultFromTuist(profile):
                logger.log(
                    level: .info,
                    "Default cache profile from Tuist's defaults has been selected: \(profile)"
                )
                return profile

            case let .defaultFromConfig(profile):
                logger.log(
                    level: .info,
                    "Default cache profile from project's configuration file has been selected: \(profile)"
                )
                return profile

            case let .selectedFromConfig(profile):
                logger.log(
                    level: .info,
                    "Selected cache profile: \(profile)"
                )
                return profile

            case let .notFound(profile, availableProfiles):
                throw CacheWarmServiceError.missingProfile(
                    name: profile,
                    availableProfiles: availableProfiles
                )
        }
    }

    private var currentPath: AbsolutePath {
        FileHandler.shared.currentPath
    }
}
