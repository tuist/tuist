import Foundation
import TSCBasic
import TuistAutomation
import TuistCache
import TuistCloud
import TuistCore
import TuistGenerator
import TuistGraph
import TuistLoader
import TuistSupport

protocol CacheControlling {
    /// Caches the cacheable targets that are part of the workspace or project at the given path.
    /// - Parameters:
    ///   - config: The project configuration.
    ///   - path: Path to the directory that contains a workspace or a project.
    ///   - cacheProfile: The caching profile.
    ///   - includedTargets: If present, a list of the targets and their dependencies to cache.
    ///   - dependenciesOnly: If true, the targets passed in the `targets` parameter are not cached, but only their dependencies
    func cache(config: Config,
               path: AbsolutePath,
               cacheProfile: TuistGraph.Cache.Profile,
               includedTargets: Set<String>,
               dependenciesOnly: Bool) async throws
}

final class CacheController: CacheControlling {
    /// Generator factory
    let generatorFactory: GeneratorFactorying

    /// Utility to build the (xc)frameworks.
    private let artifactBuilder: CacheArtifactBuilding

    private let bundleArtifactBuilder: CacheArtifactBuilding

    /// Cache graph content hasher.
    private let cacheGraphContentHasher: CacheGraphContentHashing

    /// Cache.
    private let cache: CacheStoring

    /// Cache graph linter.
    private let cacheGraphLinter: CacheGraphLinting

    convenience init(
        cache: CacheStoring,
        artifactBuilder: CacheArtifactBuilding,
        bundleArtifactBuilder: CacheArtifactBuilding,
        contentHasher: ContentHashing
    ) {
        self.init(
            cache: cache,
            artifactBuilder: artifactBuilder,
            bundleArtifactBuilder: bundleArtifactBuilder,
            generatorFactory: GeneratorFactory(contentHasher: contentHasher),
            cacheGraphContentHasher: CacheGraphContentHasher(contentHasher: contentHasher),
            cacheGraphLinter: CacheGraphLinter()
        )
    }

    init(
        cache: CacheStoring,
        artifactBuilder: CacheArtifactBuilding,
        bundleArtifactBuilder: CacheArtifactBuilding,
        generatorFactory: GeneratorFactorying,
        cacheGraphContentHasher: CacheGraphContentHashing,
        cacheGraphLinter: CacheGraphLinting
    ) {
        self.cache = cache
        self.generatorFactory = generatorFactory
        self.artifactBuilder = artifactBuilder
        self.bundleArtifactBuilder = bundleArtifactBuilder
        self.cacheGraphContentHasher = cacheGraphContentHasher
        self.cacheGraphLinter = cacheGraphLinter
    }

    func cache(
        config: Config,
        path: AbsolutePath,
        cacheProfile: TuistGraph.Cache.Profile,
        includedTargets: Set<String>,
        dependenciesOnly: Bool
    ) async throws {
        let xcframeworks = artifactBuilder.cacheOutputType == .xcframework
        let generator = generatorFactory.cache(
            config: config,
            includedTargets: includedTargets.isEmpty ? nil : Set(includedTargets),
            focusedTargets: nil,
            xcframeworks: xcframeworks,
            cacheProfile: cacheProfile
        )
        let (_, graph) = try generator.generateWithGraph(path: path, projectOnly: false)

        // Lint
        cacheGraphLinter.lint(graph: graph)

        // Hash
        logger.notice("Hashing cacheable targets")

        let hashesByTargetToBeCached = try await makeHashesByTargetToBeCached(
            for: graph,
            cacheProfile: cacheProfile,
            cacheOutputType: artifactBuilder.cacheOutputType,
            includedTargets: includedTargets,
            dependenciesOnly: dependenciesOnly
        )

        guard !hashesByTargetToBeCached.isEmpty else {
            logger.notice("All cacheable targets are already cached")
            return
        }

        logger.notice("Targets to be cached: \(hashesByTargetToBeCached.map(\.0.target.name).sorted().joined(separator: ", "))")

        logger.notice("Filtering cacheable targets")

        let targetsToBeCached = Set(hashesByTargetToBeCached.map(\.0.target.name))
        let (projectPath, updatedGraph) = try generatorFactory
            .cache(
                config: config,
                includedTargets: targetsToBeCached,
                focusedTargets: targetsToBeCached,
                xcframeworks: xcframeworks,
                cacheProfile: cacheProfile
            )
            .generateWithGraph(path: path, projectOnly: false)

        logger.notice("Building cacheable targets")

        try await archive(updatedGraph, projectPath: projectPath, cacheProfile: cacheProfile, hashesByTargetToBeCached)

        logger.notice(
            "All cacheable targets have been cached successfully as \(artifactBuilder.cacheOutputType.description)s",
            metadata: .success
        )
    }

    // swiftlint:disable:next function_body_length
    private func archive(
        _ graph: Graph,
        projectPath: AbsolutePath,
        cacheProfile: TuistGraph.Cache.Profile,
        _ hashesByCacheableTarget: [(GraphTarget, String)]
    ) async throws {
        let binariesSchemes = graph.workspace.schemes
            .filter { $0.name.contains(Constants.AutogeneratedScheme.binariesSchemeNamePrefix) }
            .filter { !($0.buildAction?.targets ?? []).isEmpty }
        let bundlesSchemes = graph.workspace.schemes
            .filter { $0.name.contains(Constants.AutogeneratedScheme.bundlesSchemeNamePrefix) }
            .filter { !($0.buildAction?.targets ?? []).isEmpty }

        try await FileHandler.shared.inTemporaryDirectory { outputDirectory in
            for scheme in binariesSchemes {
                let outputDirectory = outputDirectory.appending(component: scheme.name)
                try FileHandler.shared.createFolder(outputDirectory)
                try await self.artifactBuilder.build(
                    scheme: scheme,
                    projectTarget: XcodeBuildTarget(with: projectPath),
                    configuration: cacheProfile.configuration,
                    osVersion: cacheProfile.os,
                    deviceName: cacheProfile.device,
                    into: outputDirectory
                )
            }

            for scheme in bundlesSchemes {
                let outputDirectory = outputDirectory.appending(component: scheme.name)
                try FileHandler.shared.createFolder(outputDirectory)
                try await self.bundleArtifactBuilder.build(
                    scheme: scheme,
                    projectTarget: XcodeBuildTarget(with: projectPath),
                    configuration: cacheProfile.configuration,
                    osVersion: cacheProfile.os,
                    deviceName: cacheProfile.device,
                    into: outputDirectory
                )
            }

            let targetsToStore = hashesByCacheableTarget.map(\.0.target.name).sorted().joined(separator: ", ")
            logger.notice("Storing \(hashesByCacheableTarget.count) cacheable targets: \(targetsToStore)")
            try await self.store(hashesByCacheableTarget, outputDirectory: outputDirectory)
        }
    }

    func store(
        _ hashesByCacheableTarget: [(GraphTarget, String)],
        outputDirectory: AbsolutePath
    ) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            for (target, hash) in hashesByCacheableTarget {
                let isBinary = target.target.product.isFramework
                let suffix =
                    "\(isBinary ? Constants.AutogeneratedScheme.binariesSchemeNamePrefix : Constants.AutogeneratedScheme.bundlesSchemeNamePrefix)-\(target.target.platform.caseValue)"
                let productNameWithExtension = target.target.productName
                group.addTask {
                    try await self.cache.store(
                        name: target.target.name,
                        hash: hash,
                        paths: FileHandler.shared.glob(
                            outputDirectory.appending(component: suffix),
                            glob: "\(productNameWithExtension).*"
                        )
                    )
                }
            }
            try await group.waitForAll()
        }
    }

    func makeHashesByTargetToBeCached(
        for graph: Graph,
        cacheProfile: TuistGraph.Cache.Profile,
        cacheOutputType: CacheOutputType,
        includedTargets: Set<String>,
        dependenciesOnly: Bool
    ) async throws -> [(GraphTarget, String)] {
        // When `dependenciesOnly` is true, there is no need to compute `includedTargets` hashes
        let excludedTargets = dependenciesOnly ? includedTargets : []
        let hashesByCacheableTarget = try cacheGraphContentHasher.contentHashes(
            for: graph,
            cacheProfile: cacheProfile,
            cacheOutputType: cacheOutputType,
            excludedTargets: excludedTargets
        )

        let graphTraverser = GraphTraverser(graph: graph)

        let graph = try topologicalSort(
            Array(graphTraverser.allTargets()),
            successors: {
                Array(graphTraverser.directTargetDependencies(path: $0.path, name: $0.target.name))
            }
        )
        return try await graph.concurrentCompactMap { target in
            guard
                let hash = hashesByCacheableTarget[target],
                // if cache already exists, no need to build
                try await !self.cache.exists(name: target.target.name, hash: hash)
            else {
                return nil
            }
            return (target, hash)
        }
        .reversed()
    }
}
