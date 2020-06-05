import Foundation
import RxSwift
import TSCBasic
import TuistCore

public final class Cache: CacheStoraging {
    // MARK: - Attributes

    /// Storages where the targest will be cached.
    private let storages: [CacheStoraging]

    // MARK: - Init

    public convenience init() {
        self.init(storages: [CacheLocalStorage()])
    }

    /// Initializes the cache with its attributes.
    /// - Parameter storages: Storages where the targest will be cached.
    init(storages: [CacheStoraging]) {
        self.storages = storages
    }

    // MARK: - CacheStoraging

    public func exists(hash: String, userConfig: Config) -> Single<Bool> {
        /// It calls exists sequentially until one of the storages returns true.
        storages.map { $0.exists(hash: hash, userConfig: userConfig) }.reduce(Single.just(false)) { (result, next) -> Single<Bool> in
            result.flatMap { exists in
                if exists {
                    return Single.just(exists)
                } else {
                    return next
                }
            }.catchError { (_) -> Single<Bool> in
                next
            }
        }
    }

    public func fetch(hash: String, userConfig: Config) -> Single<AbsolutePath> {
        storages
            .map { $0.fetch(hash: hash, userConfig: userConfig) }
            .reduce(nil) { (result, next) -> Single<AbsolutePath> in
                if let result = result {
                    return result.catchError { _ in next }
                } else {
                    return next
                }
            }!
    }

    public func store(hash: String, userConfig: Config, xcframeworkPath: AbsolutePath) -> Completable {
        Completable.zip(storages.map { $0.store(hash: hash, userConfig: userConfig, xcframeworkPath: xcframeworkPath) })
    }
}
