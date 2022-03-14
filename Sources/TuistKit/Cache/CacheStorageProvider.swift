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

    init(config: Config) {
        self.config = config
        cacheDirectoryProviderFactory = CacheDirectoriesProviderFactory()
        cloudAuthenticationController = CloudAuthenticationController()
    }

    func storages() throws -> [CacheStoring] {
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
                    logger.warning("Authentication token for tuist cloud was not found. Skipping using remote cache. Run `tuist cloud auth` to authenticate yourself.")
                } else {
                    throw CacheStorageProviderError.tokenNotFound
                }
            }
        }
        return storages
    }
}
