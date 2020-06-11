import Foundation
import RxSwift
import TSCBasic
import TuistCore

public protocol CacheStoring {
    /// Returns if the target with the given hash exists in the cache.
    /// - Parameters:
    ///   - hash: Target's hash.
    ///   - userConfig: The user configuration.
    /// - Returns: An observable that returns a boolean indicating whether the target is cached.
    func exists(hash: String, config: Config) -> Single<Bool>

    /// For the target with the given hash, it fetches it from the cache and returns a path
    /// pointint to the .xcframework that represents it.
    ///
    /// - Parameters:
    ///   - hash: Target's hash.
    ///   - userConfig: The user configuration.
    /// - Returns: An observable that returns a boolean indicating whether the target is cached.
    func fetch(hash: String, config: Config) -> Single<AbsolutePath>

    /// It stores the xcframework at the given path in the cache.
    /// - Parameters:
    ///   - hash: Hash of the target the xcframework belongs to.
    ///   - userConfig: The user configuration.
    ///   - xcframeworkPath: Path to the .xcframework.
    func store(hash: String, config: Config, xcframeworkPath: AbsolutePath) -> Completable
}
