import Foundation
import RxBlocking
import RxSwift
import TSCBasic
import TuistAutomation
import TuistCache
import TuistCore
import TuistGenerator
import TuistLoader
import TuistScale
import TuistSupport

protocol CacheControlling {
    /// Caches the cacheable targets that are part of the workspace or project at the given path.
    /// - Parameter path: Path to the directory that contains a workspace or a project.
    func cache(path: AbsolutePath) throws
}

final class CacheController: CacheControlling {
    /// Xcode project generator.
    private let generator: ProjectGenerating

    /// Utility to build the xcframeworks.
    private let xcframeworkBuilder: XCFrameworkBuilding

    /// Graph content hasher.
    private let graphContentHasher: GraphContentHashing

    /// Cache.
    private let cache: CacheStoring

    convenience init(cache: CacheStoring) {
        self.init(cache: cache,
                  generator: ProjectGenerator(),
                  xcframeworkBuilder: XCFrameworkBuilder(xcodeBuildController: XcodeBuildController()),
                  graphContentHasher: GraphContentHasher())
    }

    init(cache: CacheStoring,
         generator: ProjectGenerating,
         xcframeworkBuilder: XCFrameworkBuilding,
         graphContentHasher: GraphContentHashing)
    {
        self.cache = cache
        self.generator = generator
        self.xcframeworkBuilder = xcframeworkBuilder
        self.graphContentHasher = graphContentHasher
    }

    func cache(path: AbsolutePath) throws {
        let (path, graph) = try generator.generateWithGraph(path: path, projectOnly: false)

        logger.notice("Hashing cacheable frameworks")
        let cacheableTargets = try self.cacheableTargets(graph: graph)

        let completables = try cacheableTargets.map { try buildAndCacheXCFramework(path: path, target: $0.key, hash: $0.value) }
        _ = try Completable.zip(completables).toBlocking().last()

        logger.notice("All cacheable frameworks have been cached successfully", metadata: .success)
    }

    /// Returns all the targets that are cacheable and their hashes.
    /// - Parameter graph: Graph that contains all the dependency graph nodes.
    fileprivate func cacheableTargets(graph: Graph) throws -> [TargetNode: String] {
        try graphContentHasher.contentHashes(for: graph)
            .filter { target, hash in
                if let exists = try self.cache.exists(hash: hash).toBlocking().first(), exists {
                    logger.pretty("The target \(.bold(.raw(target.name))) with hash \(.bold(.raw(hash))) is already in the cache. Skipping...")
                    return false
                }
                return true
            }
    }

    /// Builds the .xcframework for the given target and returns an obervable to store them in the cache.
    /// - Parameters:
    ///   - path: Path to either the .xcodeproj or .xcworkspace that contains the framework to be cached.
    ///   - target: Target whose .xcframework will be built and cached.
    ///   - hash: Hash of the target.
    fileprivate func buildAndCacheXCFramework(path: AbsolutePath, target: TargetNode, hash: String) throws -> Completable {
        // Build targets sequentially
        let xcframeworkPath: AbsolutePath!

        // Note: Since building XCFrameworks involves calling xcodebuild, we run the building process sequentially.
        if path.extension == "xcworkspace" {
            xcframeworkPath = try xcframeworkBuilder.build(workspacePath: path, target: target.target).toBlocking().single()
        } else {
            xcframeworkPath = try xcframeworkBuilder.build(projectPath: path, target: target.target).toBlocking().single()
        }

        // Create tasks to cache and delete the xcframeworks asynchronously
        let deleteXCFrameworkCompletable = Completable.create(subscribe: { completed in
            try? FileHandler.shared.delete(xcframeworkPath)
            completed(.completed)
            return Disposables.create()
        })
        return cache
            .store(hash: hash, xcframeworkPath: xcframeworkPath)
            .concat(deleteXCFrameworkCompletable)
            .catchError { error in
                // We propagate the error downstream
                deleteXCFrameworkCompletable.concat(Completable.error(error))
            }
    }
}
