import Foundation
import RxBlocking
import RxSwift
import TSCBasic
import TuistAutomation
import TuistCache
import TuistCloud
import TuistCore
import TuistGenerator
import TuistLoader
import TuistSupport

/// A provider that concatenates the default mappers, to the mapper that adds the build phase
/// to locate the built products directory.
class CacheControllerProjectMapperProvider: ProjectMapperProviding {
    func mapper(config: Config) -> ProjectMapping {
        let defaultProjectMapperProvider = ProjectMapperProvider()
        let defaultMapper = defaultProjectMapperProvider.mapper(config: config)
        return SequentialProjectMapper(mappers: [defaultMapper, CacheBuildPhaseProjectMapper()])
    }
}

protocol CacheControllerProjectGeneratorProviding {
    /// Returns an instance of the project generator that should be used to generate the projects for caching.
    /// - Returns: An instance of the project generator.
    func generator() -> Generating
}

/// A provider that returns the project generator that should be used by the cache controller.
class CacheControllerProjectGeneratorProvider: CacheControllerProjectGeneratorProviding {
    func generator() -> Generating {
        let projectMapperProvider = CacheControllerProjectMapperProvider()
        return Generator(projectMapperProvider: projectMapperProvider,
                         workspaceMapperProvider: WorkspaceMapperProvider(projectMapperProvider: projectMapperProvider))
    }
}

protocol CacheControlling {
    /// Caches the cacheable targets that are part of the workspace or project at the given path.
    /// - Parameters:
    ///   - path: Path to the directory that contains a workspace or a project.
    func cache(path: AbsolutePath) throws
}

final class CacheController: CacheControlling {
    /// Project generator provider.
    let projectGeneratorProvider: CacheControllerProjectGeneratorProviding

    /// Utility to build the (xc)frameworks.
    private let artifactBuilder: CacheArtifactBuilding

    /// Graph content hasher.
    private let graphContentHasher: GraphContentHashing

    /// Cache.
    private let cache: CacheStoring

    convenience init(cache: CacheStoring, artifactBuilder: CacheArtifactBuilding) {
        self.init(cache: cache,
                  artifactBuilder: artifactBuilder,
                  projectGeneratorProvider: CacheControllerProjectGeneratorProvider(),
                  graphContentHasher: GraphContentHasher())
    }

    init(cache: CacheStoring,
         artifactBuilder: CacheArtifactBuilding,
         projectGeneratorProvider: CacheControllerProjectGeneratorProviding,
         graphContentHasher: GraphContentHashing)
    {
        self.cache = cache
        self.projectGeneratorProvider = projectGeneratorProvider
        self.artifactBuilder = artifactBuilder
        self.graphContentHasher = graphContentHasher
    }

    func cache(path: AbsolutePath) throws {
        let generator = projectGeneratorProvider.generator()
        let (path, graph) = try generator.generateWithGraph(path: path, projectOnly: false)

        logger.notice("Hashing cacheable frameworks")
        let cacheableTargets = try self.cacheableTargets(graph: graph)

        logger.notice("Building cacheable frameworks as \(artifactBuilder.cacheOutputType.description)s")

        try cacheableTargets.sorted(by: { $0.key.target.name < $1.key.target.name }).forEach { target, hash in
            try self.buildAndCacheFramework(path: path, target: target, hash: hash)
        }

        logger.notice("All cacheable frameworks have been cached successfully as \(artifactBuilder.cacheOutputType.description)s", metadata: .success)
    }

    /// Returns all the targets that are cacheable and their hashes.
    /// - Parameter graph: Graph that contains all the dependency graph nodes.
    fileprivate func cacheableTargets(graph: Graph) throws -> [TargetNode: String] {
        try graphContentHasher.contentHashes(for: graph, cacheOutputType: artifactBuilder.cacheOutputType)
            .filter { target, hash in
                if let exists = try self.cache.exists(hash: hash).toBlocking().first(), exists {
                    logger.pretty("The target \(.bold(.raw(target.name))) with hash \(.bold(.raw(hash))) and type \(artifactBuilder.cacheOutputType.description) is already in the cache. Skipping...")
                    return false
                }
                return true
            }
    }

    /// Builds the .xcframework for the given target and returns an obervable to store them in the cache.
    /// - Parameters:
    ///   - path: Path to either the .xcodeproj or .xcworkspace that contains the framework to be cached.
    ///   - target: Target whose .(xc)framework will be built and cached.
    ///   - hash: Hash of the target.
    fileprivate func buildAndCacheFramework(path: AbsolutePath,
                                            target: TargetNode,
                                            hash: String) throws
    {
        let outputDirectory = try FileHandler.shared.temporaryDirectory()
        defer {
            try? FileHandler.shared.delete(outputDirectory)
        }

        if path.extension == "xcworkspace" {
            try artifactBuilder.build(workspacePath: path,
                                      target: target.target,
                                      into: outputDirectory)
        } else {
            try artifactBuilder.build(projectPath: path,
                                      target: target.target,
                                      into: outputDirectory)
        }

        _ = try cache.store(hash: hash, paths: FileHandler.shared.glob(outputDirectory, glob: "*")).toBlocking().last()
    }
}
