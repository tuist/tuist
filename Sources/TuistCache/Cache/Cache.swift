import Foundation
import RxSwift
import TSCBasic
import TuistCore

public final class Cache: CacheStoring {
    // MARK: - Attributes

    private let storageProvider: CacheStorageProviding

    /// An instance that returns the storages to be used.
    private var storages: [CacheStoring] {
        (try? storageProvider.storages()) ?? []
    }

    // MARK: - Init

    /// Initializes the cache with its attributes.
    /// - Parameter storageProvider: An instance that returns the storages to be used.
    public init(storageProvider: CacheStorageProviding) {
        self.storageProvider = storageProvider
    }

    // MARK: - CacheStoring

    public func exists(hash: String) -> Single<Bool> {
        /// It calls exists sequentially until one of the storages returns true.
        return storages.map { $0.exists(hash: hash) }.reduce(Single.just(false)) { (result, next) -> Single<Bool> in
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

    public func fetch(hash: String) -> Single<AbsolutePath> {
        return storages
            .map { $0.fetch(hash: hash) }
            .reduce(nil) { (result, next) -> Single<AbsolutePath> in
                if let result = result {
                    return result.catchError { _ in next }
                } else {
                    return next
                }
            }!
    }

    public func store(hash: String, paths: [AbsolutePath]) -> Completable {
        return Completable.zip(storages.map { $0.store(hash: hash, paths: paths) })
    }
}
