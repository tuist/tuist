import Foundation
import TSCBasic
import TuistCache
import TuistCore
import TuistGraph
import TuistLoader
import TuistSupport

enum CacheWarmServiceError: FatalError, Equatable {
    case missingDefaultProfile
    case missingProfile(name: String, availableProfiles: [String])

    /// Error description.
    var description: String {
        switch self {
        case let .missingProfile(name, availableProfiles):
            return "The profile '\(name)' is missing in your project's configuration. Available cache profiles: \(availableProfiles.listed())."

        case .missingDefaultProfile:
            return "The default profile has not been found."
        }
    }

    /// Error type.
    var type: ErrorType {
        switch self {
        case .missingProfile:
            return .abort
        case .missingDefaultProfile:
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

    // TODO: Add unit tests
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
        let profiles = config.cache.profiles
        switch profileName {
        case .none:
            guard let defaultProfile = profiles.first else {
                throw CacheWarmServiceError.missingDefaultProfile
            }
            return defaultProfile

        case let .some(name):
            guard let profile = profiles.first(where: { $0.name == name }) else {
                throw CacheWarmServiceError.missingProfile(name: name, availableProfiles: profiles.map(\.name))
            }
            return profile
        }
    }

    private var currentPath: AbsolutePath {
        FileHandler.shared.currentPath
    }
}
