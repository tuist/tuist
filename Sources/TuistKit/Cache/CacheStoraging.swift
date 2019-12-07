import Basic
import Foundation
import RxSwift

protocol CacheStoraging {
    /// Returns if the target with the given hash exists in the cache.
    /// - Parameter hash: Target's hash.
    /// - Returns: An observable that returns a boolean indicating whether the target is cached.
    func exists(hash: String) -> Single<Bool>

    /// For the target with the given hash, it fetches it from the cache and returns a path
    /// pointint to the .xcframework that represents it.
    ///
    /// - Parameter hash: Target's hash.
    /// - Returns: An observable that returns a boolean indicating whether the target is cached.
    func fetch(hash: String) -> Single<AbsolutePath>

    func store(hash: String, path: AbsolutePath) -> Completable
}
