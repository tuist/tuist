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
    private let cloudURLService: CloudURLServicing

    /// Cached response for list of storages
    @Atomic
    static var storages: [CacheStoring]?

    convenience init(
        config: Config
    ) {
        self.init(
            config: config,
            cacheDirectoryProviderFactory: CacheDirectoriesProviderFactory(),
            cloudAuthenticationController: CloudAuthenticationController(),
            cloudURLService: CloudURLService()
        )
    }

    init(
        config: Config,
        cacheDirectoryProviderFactory: CacheDirectoriesProviderFactoring,
        cloudAuthenticationController: CloudAuthenticationControlling,
        cloudURLService: CloudURLServicing
    ) {
        self.config = config
        self.cacheDirectoryProviderFactory = cacheDirectoryProviderFactory
        self.cloudAuthenticationController = cloudAuthenticationController
        self.cloudURLService = cloudURLService
    }

    func storages() throws -> [CacheStoring] {
        if let storages = Self.storages {
            return storages
        }
        let cacheDirectoriesProvider = try cacheDirectoryProviderFactory.cacheDirectories(config: config)
        var storages: [CacheStoring] = [CacheLocalStorage(cacheDirectoriesProvider: cacheDirectoriesProvider)]

        if var cloudConfig = config.cloud {
            let url = try cloudURLService.url(serverURL: config.cloud?.url.absoluteString)
            cloudConfig = cloudConfig.withURL(url: url)
            if try cloudAuthenticationController.authenticationToken(serverURL: url)?.isEmpty == false {
                let remoteStorage = CacheRemoteStorage(
                    cloudConfig: cloudConfig,
                    cacheDirectoriesProvider: cacheDirectoriesProvider
                )
                let storage = RetryingCacheStorage(cacheStoring: remoteStorage)
                storages.append(storage)
            } else {
                if cloudConfig.options.contains(.optional) {
                    logger
                        .warning(
                            "Authentication token for Tuist Cloud was not found. Skipping using remote cache. Run `tuist cloud auth` to authenticate yourself."
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
