import Basic
import Foundation
import RxSwift

final class Cache: CacheStoraging {
    // MARK: - Attributes

    /// Storages where the targest will be cached.
    private let storages: [CacheStoraging]

    // MARK: - Init

    /// Initializes the cache with its attributes.
    /// - Parameter storages: Storages where the targest will be cached.
    init(storages: [CacheStoraging] = [CacheLocalStorage()]) {
        self.storages = storages
    }

    // MARK: - CacheStoraging

    func exists(hash: String) -> Single<Bool> {
        /// It calls exists sequentially until one of the storages returns true.
        storages.map { $0.exists(hash: hash) }.reduce(Single.just(false)) { (result, next) -> Single<Bool> in
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

    func fetch(hash: String) -> Single<AbsolutePath> {
        storages
            .map { $0.fetch(hash: hash) }
            .reduce(nil) { (result, next) -> Single<AbsolutePath> in
                if let result = result {
                    return result.catchError { _ in next }
                } else {
                    return next
                }
            }!
    }

    func store(hash: String, path: AbsolutePath) -> Completable {
        Completable.zip(storages.map { $0.store(hash: hash, path: path) })
    }
}
