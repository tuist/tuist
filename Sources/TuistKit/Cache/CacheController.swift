import Foundation
import RxBlocking
import RxSwift
import TSCBasic
import TuistAutomation
import TuistCache
import TuistCloud
import TuistCore
import TuistGenerator
import TuistGraph
import TuistLoader
import TuistSupport

/// A provider that concatenates the default mappers, to the mapper that adds the build phase
/// to locate the built products directory.
class CacheControllerProjectMapperProvider: ProjectMapperProviding {
    fileprivate let contentHasher: ContentHashing
    init(contentHasher: ContentHashing) {
        self.contentHasher = contentHasher
    }

    func mapper(config: Config) -> ProjectMapping {
        let defaultProjectMapperProvider = ProjectMapperProvider(contentHasher: contentHasher)
        let defaultMapper = defaultProjectMapperProvider.mapper(config: config)
        return SequentialProjectMapper(mappers: [defaultMapper])
    }
}

protocol CacheControllerProjectGeneratorProviding {
    /// Returns an instance of the project generator that should be used to generate the projects for caching.
    /// - Returns: An instance of the project generator.
    func generator() -> Generating
}

/// A provider that returns the project generator that should be used by the cache controller.
class CacheControllerProjectGeneratorProvider: CacheControllerProjectGeneratorProviding {
    fileprivate let contentHasher: ContentHashing
    init(contentHasher: ContentHashing) {
        self.contentHasher = contentHasher
    }

    func generator() -> Generating {
        let contentHasher = CacheContentHasher()
        let projectMapperProvider = CacheControllerProjectMapperProvider(contentHasher: contentHasher)
        let workspaceMapperProvider = WorkspaceMapperProvider(projectMapperProvider: projectMapperProvider)
        return Generator(projectMapperProvider: projectMapperProvider,
                         graphMapperProvider: GraphMapperProvider(),
                         workspaceMapperProvider: workspaceMapperProvider,
                         manifestLoaderFactory: ManifestLoaderFactory())
    }
}

protocol CacheControlling {
    /// Caches the cacheable targets that are part of the workspace or project at the given path.
    /// - Parameters:
    ///   - path: Path to the directory that contains a workspace or a project.
    ///   - cacheProfile: The caching profile.
    ///   - targets: If present, a list of target to build.
    func cache(path: AbsolutePath, cacheProfile: TuistGraph.Cache.Profile, targetsToFilter: [String]) throws
}

final class CacheController: CacheControlling {
    /// Project generator provider.
    let projectGeneratorProvider: CacheControllerProjectGeneratorProviding

    /// Utility to build the (xc)frameworks.
    private let artifactBuilder: CacheArtifactBuilding

    /// Cache graph content hasher.
    private let cacheGraphContentHasher: CacheGraphContentHashing

    /// Cache.
    private let cache: CacheStoring

    /// Cache graph linter.
    private let cacheGraphLinter: CacheGraphLinting

    convenience init(cache: CacheStoring,
                     artifactBuilder: CacheArtifactBuilding,
                     contentHasher: ContentHashing)
    {
        self.init(cache: cache,
                  artifactBuilder: artifactBuilder,
                  projectGeneratorProvider: CacheControllerProjectGeneratorProvider(contentHasher: contentHasher),
                  cacheGraphContentHasher: CacheGraphContentHasher(contentHasher: contentHasher),
                  cacheGraphLinter: CacheGraphLinter())
    }

    init(cache: CacheStoring,
         artifactBuilder: CacheArtifactBuilding,
         projectGeneratorProvider: CacheControllerProjectGeneratorProviding,
         cacheGraphContentHasher: CacheGraphContentHashing,
         cacheGraphLinter: CacheGraphLinting)
    {
        self.cache = cache
        self.projectGeneratorProvider = projectGeneratorProvider
        self.artifactBuilder = artifactBuilder
        self.cacheGraphContentHasher = cacheGraphContentHasher
        self.cacheGraphLinter = cacheGraphLinter
    }

    func cache(path: AbsolutePath, cacheProfile: TuistGraph.Cache.Profile, targetsToFilter: [String]) throws {
        let generator = projectGeneratorProvider.generator()
        let (projectPath, graph) = try generator.generateWithGraph(path: path, projectOnly: false)

        // Lint
        cacheGraphLinter.lint(graph: graph)

        // Hash
        logger.notice("Hashing cacheable targets")
        let hashesByCacheableTarget = try cacheGraphContentHasher.contentHashes(
            for: graph,
            cacheProfile: cacheProfile,
            cacheOutputType: artifactBuilder.cacheOutputType
        )

        let filteredTargets: [TargetNode]
        if targetsToFilter.isEmpty {
            filteredTargets = Array(hashesByCacheableTarget.keys)
        } else {
            filteredTargets = Array(hashesByCacheableTarget.keys.filter { targetsToFilter.contains($0.name) })
        }

        logger.notice("Removing Bundle targets")
        let filteredTargetsWithoutBundles = filteredTargets.filter { $0.target.product != .bundle }

        logger.notice("Building cacheable targets")
        let sortedCacheableTargets = try topologicalSort(filteredTargetsWithoutBundles, successors: \.targetDependencies)

        for (index, target) in sortedCacheableTargets.reversed().enumerated() {
            logger.notice("Building cacheable targets: \(target.name), \(index + 1) out of \(sortedCacheableTargets.count)")

            let hash = hashesByCacheableTarget[target]!

            if let exists = try cache.exists(hash: hash).toBlocking().first(), exists {
                logger.pretty("The target \(.bold(.raw(target.name))) with hash \(.bold(.raw(hash))) and type \(artifactBuilder.cacheOutputType.description) is already in the cache. Skipping...")
                continue
            }

            // Build
            try buildAndCacheFramework(path: projectPath, target: target, configuration: cacheProfile.configuration, hash: hash)
        }

        logger.notice("All cacheable targets have been cached successfully as \(artifactBuilder.cacheOutputType.description)s", metadata: .success)
    }

    /// Builds the .xcframework for the given target and returns an obervable to store them in the cache.
    /// - Parameters:
    ///   - path: Path to either the .xcodeproj or .xcworkspace that contains the framework to be cached.
    ///   - target: Target whose .(xc)framework will be built and cached.
    ///   - configuration: The configuration.
    ///   - hash: Hash of the target.
    fileprivate func buildAndCacheFramework(path: AbsolutePath,
                                            target: TargetNode,
                                            configuration: String,
                                            hash: String) throws
    {
        let outputDirectory = try FileHandler.shared.temporaryDirectory()
        defer {
            try? FileHandler.shared.delete(outputDirectory)
        }

        if path.extension == "xcworkspace" {
            try artifactBuilder.build(workspacePath: path,
                                      target: target.target,
                                      configuration: configuration,
                                      into: outputDirectory)
        } else {
            try artifactBuilder.build(projectPath: path,
                                      target: target.target,
                                      configuration: configuration,
                                      into: outputDirectory)
        }

        _ = try cache.store(hash: hash, paths: FileHandler.shared.glob(outputDirectory, glob: "*")).toBlocking().last()
    }
}
