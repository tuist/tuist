import Foundation
import TSCBasic
import TuistCore

public protocol CacheStoring {
    /// Returns if the target with the given hash exists in the cache.
    /// - Parameters:
    ///   - name: Target's name.
    ///   - hash: Target's hash.
    /// - Returns: An observable that returns a boolean indicating whether the target is cached.
    func exists(name: String, hash: String) async throws -> Bool

    /// For the target with the given hash, it fetches it from the cache and returns a path
    /// pointint to the .xcframework that represents it.
    ///
    /// - Parameters:
    ///   - name: Target's name.
    ///   - hash: Target's hash.
    /// - Returns: An observable that returns a boolean indicating whether the target is cached.
    func fetch(name: String, hash: String) async throws -> AbsolutePath

    /// It stores the xcframework at the given path in the cache.
    /// - Parameters:
    ///   - name: Target's name.
    ///   - hash: Hash of the target the xcframework belongs to.
    ///   - paths: Path to the files that will be stored.
    func store(name: String, hash: String, paths: [AbsolutePath]) async throws
}
