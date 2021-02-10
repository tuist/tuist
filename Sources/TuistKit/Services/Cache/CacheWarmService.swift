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

    func run(path: String?, profile: String?, xcframeworks: Bool, targets: [String]) throws {
        let path = self.path(path)
        let config = try generatorModelLoader.loadConfig(at: path)
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
        try cacheController.cache(path: path, configuration: profile.configuration, targetsToFilter: targets)
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
            return profile

        case let .defaultFromConfig(profile):
            return profile

        case let .selectedFromConfig(profile):
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
