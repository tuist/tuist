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

    public func exists(name: String, hash: String) -> Single<Bool> {
        /// It calls exists sequentially until one of the storages returns true.
        storages.reduce(Single.just(false)) { result, next -> Single<Bool> in
            result.flatMap { exists in
                guard !exists else { return result }
                return next.exists(name: name, hash: hash)
            }.catchError { _ -> Single<Bool> in
                next.exists(name: name, hash: hash)
            }
        }
    }

    public func fetch(name: String, hash: String) -> Single<AbsolutePath> {
        storages
            .reduce(nil) { result, next -> Single<AbsolutePath> in
                if let result = result {
                    return result.catchError { _ in next.fetch(name: name, hash: hash) }
                } else {
                    return next.fetch(name: name, hash: hash)
                }
            }!
    }

    public func store(name: String, hash: String, paths: [AbsolutePath]) -> Completable {
        Completable.zip(storages.map { $0.store(name: name, hash: hash, paths: paths) })
    }
}
