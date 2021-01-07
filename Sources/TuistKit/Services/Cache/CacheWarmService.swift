import Foundation
import TSCBasic
import TuistCache
import TuistCore
import TuistLoader
import TuistSupport

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
    func run(path: String?, flavor: String?, xcframeworks: Bool) throws {
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
        let flavor = try cacheFlavor(named: flavor, from: config)
        try cacheController.cache(path: path, configuration: flavor.configuration)
    }

    // MARK: - Helpers

    private func path(_ path: String?) -> AbsolutePath {
        if let path = path {
            return AbsolutePath(path, relativeTo: currentPath)
        } else {
            return currentPath
        }
    }

    private func cacheFlavor(named flavorName: String?, from config: Config) throws -> TuistCore.Cache.Flavor {
        let flavors = config.cache.flavors
        switch flavorName {
            case .none:
                guard let defaultFlavor = flavors.first else {
                    throw CacheWarmServiceError.missingDefaultFlavor
                }
                return defaultFlavor

            case let .some(name):
                guard let flavor = flavors.first(where: { $0.name == name }) else {
                    throw CacheWarmServiceError.missingFlavor(name: name, availableFlavors: flavors.map(\.name))
                }
                return flavor
        }
    }

    private var currentPath: AbsolutePath {
        FileHandler.shared.currentPath
    }
}

enum CacheWarmServiceError: FatalError, Equatable {
    case missingDefaultFlavor
    case missingFlavor(name: String, availableFlavors: [String])

    /// Error description.
    var description: String {
        switch self {
        case let .missingFlavor(name, availableFlavors):
            return "The flavor '\(name)' is missing in your project's configuration. Available cache flavors: \(availableFlavors.joined(separator: ", "))."

        case .missingDefaultFlavor:
            return "The default flavor has not been found."
        }
    }

    /// Error type.
    var type: ErrorType {
        switch self {
        case .missingFlavor:
            return .abort
        case .missingDefaultFlavor:
            return .abort
        }
    }
}
