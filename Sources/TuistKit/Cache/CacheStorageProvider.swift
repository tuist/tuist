import Foundation
import TuistCache
import TuistCloud
import TuistCore
import TuistGraph
import TuistLoader
import TuistSupport

enum CacheStorageProviderError: FatalError, Equatable {
    case tokenNotFound

    public var type: ErrorType {
        switch self {
        case .tokenNotFound:
            return .abort
        }
    }

    public var description: String {
        switch self {
        case .tokenNotFound:
            return "Token for tuist cloud was not found. Run `tuist cloud auth` to authenticate yourself."
        }
    }
}

final class CacheStorageProvider: CacheStorageProviding {
    private let config: Config
    private let cacheDirectoryProviderFactory: CacheDirectoriesProviderFactoring
    private let cloudAuthenticationController: CloudAuthenticationControlling

    /// Cached response for list of storages
    @Atomic
    static var storages: [CacheStoring]?

    convenience init(
        config: Config
    ) {
        self.init(
            config: config,
            cacheDirectoryProviderFactory: CacheDirectoriesProviderFactory(),
            cloudAuthenticationController: CloudAuthenticationController()
        )
    }

    init(
        config: Config,
        cacheDirectoryProviderFactory: CacheDirectoriesProviderFactoring,
        cloudAuthenticationController: CloudAuthenticationControlling
    ) {
        self.config = config
        self.cacheDirectoryProviderFactory = cacheDirectoryProviderFactory
        self.cloudAuthenticationController = cloudAuthenticationController
    }

    func storages() throws -> [CacheStoring] {
        if let storages = Self.storages {
            return storages
        }
        let cacheDirectoriesProvider = try cacheDirectoryProviderFactory.cacheDirectories(config: config)
        var storages: [CacheStoring] = [CacheLocalStorage(cacheDirectoriesProvider: cacheDirectoriesProvider)]
        if let cloudConfig = config.cloud {
            if try cloudAuthenticationController.authenticationToken(serverURL: cloudConfig.url)?.isEmpty == false {
                let storage = CacheRemoteStorage(
                    cloudConfig: cloudConfig,
                    cloudClient: CloudClient(),
                    cacheDirectoriesProvider: cacheDirectoriesProvider
                )
                storages.append(storage)
            } else {
                if cloudConfig.options.contains(.optional) {
                    logger
                        .warning(
                            "Authentication token for tuist cloud was not found. Skipping using remote cache. Run `tuist cloud auth` to authenticate yourself."
                        )
                } else {
                    throw CacheStorageProviderError.tokenNotFound
                }
            }
        }
        Self.storages = storages
        return storages
    }
}
