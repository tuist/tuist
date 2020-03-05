import Basic
import Foundation
import RxSwift

public protocol CacheStoraging {
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

    /// It stores the xcframework at the given path in the cache.
    /// - Parameters:
    ///   - hash: Hash of the target the xcframework belongs to.
    ///   - xcframeworkPath: Path to the .xcframework.
    func store(hash: String, xcframeworkPath: AbsolutePath) -> Completable
}
