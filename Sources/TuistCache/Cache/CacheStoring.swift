import Foundation
import RxSwift
import TSCBasic
import TuistCore

public protocol CacheStoring {
    /// Returns if the target with the given hash exists in the cache.
    /// - Parameters:
    ///   - hash: Target's hash.
    /// - Returns: An observable that returns a boolean indicating whether the target is cached.
    func exists(hash: String) -> Single<Bool>

    /// For the target with the given hash, it fetches it from the cache and returns a path
    /// pointint to the .xcframework that represents it.
    ///
    /// - Parameters:
    ///   - hash: Target's hash.
    /// - Returns: An observable that returns a boolean indicating whether the target is cached.
    func fetch(hash: String) -> Single<AbsolutePath>

    /// It stores the xcframework at the given path in the cache.
    /// - Parameters:
    ///   - hash: Hash of the target the xcframework belongs to.
    ///   - paths: Path to the files that will be stored.
    func store(hash: String, paths: [AbsolutePath]) -> Completable
}
