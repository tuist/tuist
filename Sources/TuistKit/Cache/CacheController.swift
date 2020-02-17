import Basic
import Foundation
import RxBlocking
import RxSwift
import TuistCore
import TuistGalaxy
import TuistGenerator
import TuistLoader
import TuistSupport

protocol CacheControlling {
    /// Caches the cacheable targets that are part of the workspace or project at the given path.
    /// - Parameter path: Path to the directory that contains a workspace or a project.
    func cache(path: AbsolutePath) throws
}

final class CacheController: CacheControlling {
    /// Xcode project generator.
    private let generator: Generating

    /// Manifest loader.
    private let manifestLoader: ManifestLoading

    /// Utility to build the xcframeworks.
    private let xcframeworkBuilder: XCFrameworkBuilding

    /// Graph content hasher.
    private let graphContentHasher: GraphContentHashing

    /// Cache.
    private let cache: CacheStoraging

    init(generator: Generating = Generator(),
         manifestLoader: ManifestLoading = ManifestLoader(),
         xcframeworkBuilder: XCFrameworkBuilding = XCFrameworkBuilder(printOutput: false),
         cache: CacheStoraging = Cache(),
         graphContentHasher: GraphContentHashing = GraphContentHasher()) {
        self.generator = generator
        self.manifestLoader = manifestLoader
        self.xcframeworkBuilder = xcframeworkBuilder
        self.cache = cache
        self.graphContentHasher = graphContentHasher
    }

    func cache(path: AbsolutePath) throws {
        // Generate the project.
        let (path, graph) = try generator.generate(at: path, manifestLoader: manifestLoader, projectOnly: false)

        // Getting the hash
        Printer.shared.print(section: "Hashing cacheable frameworks")
        let targets: [TargetNode: String] = try graphContentHasher.contentHashes(for: graph)
            .filter { target, hash in
            if let exists = try self.cache.exists(hash: hash).toBlocking().first(), exists {
                Printer.shared.print("The target \(.bold(.raw(target.name))) with hash \(.bold(.raw(hash))) is already in the cache. Skipping...")
                return false
            }
            return true
        }

        var completables: [Completable] = []
        try targets.forEach { target, hash in
            // Build targets sequentially
            let xcframeworkPath: AbsolutePath!
            if path.extension == "xcworkspace" {
                xcframeworkPath = try self.xcframeworkBuilder.build(workspacePath: path, target: target.target)
            } else {
                xcframeworkPath = try self.xcframeworkBuilder.build(projectPath: path, target: target.target)
            }

            // Create tasks to cache and delete the xcframeworks asynchronously
            let deleteXCFrameworkCompletable = Completable.create(subscribe: { completed in
                try? FileHandler.shared.delete(xcframeworkPath)
                completed(.completed)
                return Disposables.create()
            })
            completables.append(cache.store(hash: hash, xcframeworkPath: xcframeworkPath).concat(deleteXCFrameworkCompletable))
        }

        _ = try Completable.zip(completables).toBlocking().last()

        Printer.shared.print(success: "All cacheable frameworks have been cached successfully")
    }
}
