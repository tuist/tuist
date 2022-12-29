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
    private let cacheDownloaderType: CacheDownloaderType
    private let cacheDirectoryProviderFactory: CacheDirectoriesProviderFactoring
    private let cloudAuthenticationController: CloudAuthenticationControlling

    /// Cached response for list of storages
    @Atomic
    static var storages: [CacheStoring]?

    convenience init(
        config: Config,
        cacheDownloaderType: CacheDownloaderType = .urlsession
    ) {
        self.init(
            config: config,
            cacheDownloaderType: cacheDownloaderType,
            cacheDirectoryProviderFactory: CacheDirectoriesProviderFactory(),
            cloudAuthenticationController: CloudAuthenticationController()
        )
    }

    init(
        config: Config,
        cacheDownloaderType: CacheDownloaderType,
        cacheDirectoryProviderFactory: CacheDirectoriesProviderFactoring,
        cloudAuthenticationController: CloudAuthenticationControlling
    ) {
        self.config = config
        self.cacheDownloaderType = cacheDownloaderType
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
                let remoteStorage = CacheRemoteStorage(
                    cloudConfig: cloudConfig,
                    cloudClient: CloudClient(),
                    fileClient: cacheDownloaderType.client,
                    cacheDirectoriesProvider: cacheDirectoriesProvider
                )
                let storage = RetryingCacheStorage(cacheStoring: remoteStorage)
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

private extension CacheDownloaderType {
    public var client: FileClienting {
        switch self {
        case .aria2c:
            return Aria2Client()
        case .urlsession:
            return FileClient()
        }
    }
}
