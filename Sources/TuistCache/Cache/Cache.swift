import Foundation
import RxSwift
import TSCBasic
import TuistCore

public final class Cache: CacheStoring {
    // MARK: - Attributes

    /// Storages where the targest will be cached.
    private let storages: [CacheStoring]

    // MARK: - Init

    public convenience init() {
        self.init(storages: [CacheLocalStorage()])
    }

    /// Initializes the cache with its attributes.
    /// - Parameter storages: Storages where the targest will be cached.
    init(storages: [CacheStoring]) {
        self.storages = storages
    }

    // MARK: - CacheStoring

    public func exists(hash: String, config: Config) -> Single<Bool> {
        /// It calls exists sequentially until one of the storages returns true.
        storages.map { $0.exists(hash: hash, config: config) }.reduce(Single.just(false)) { (result, next) -> Single<Bool> in
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

    public func fetch(hash: String, config: Config) -> Single<AbsolutePath> {
        storages
            .map { $0.fetch(hash: hash, config: config) }
            .reduce(nil) { (result, next) -> Single<AbsolutePath> in
                if let result = result {
                    return result.catchError { _ in next }
                } else {
                    return next
                }
            }!
    }

    public func store(hash: String, config: Config, xcframeworkPath: AbsolutePath) -> Completable {
        Completable.zip(storages.map { $0.store(hash: hash, config: config, xcframeworkPath: xcframeworkPath) })
    }
}
