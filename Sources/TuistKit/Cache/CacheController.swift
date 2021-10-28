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
        let defaultMapper = defaultProjectMapperProvider.mapper(
            config: config
        )
        return SequentialProjectMapper(mappers: [defaultMapper])
    }
}

protocol CacheControllerProjectGeneratorProviding {
    /// Returns an instance of the project generator that should be used to generate the projects for caching.
    /// - Parameter includedTargets: Targets to be filtered
    /// - Returns: An instance of the project generator.
    func generator(includedTargets: Set<String>?) -> Generating
}

/// A provider that returns the project generator that should be used by the cache controller.
class CacheControllerProjectGeneratorProvider: CacheControllerProjectGeneratorProviding {
    private let contentHasher: ContentHashing

    init(contentHasher: ContentHashing) {
        self.contentHasher = contentHasher
    }

    func generator(includedTargets: Set<String>?) -> Generating {
        let contentHasher = CacheContentHasher()
        let projectMapperProvider = CacheControllerProjectMapperProvider(contentHasher: contentHasher)
        let workspaceMapperProvider = WorkspaceMapperProvider(projectMapperProvider: projectMapperProvider)
        let cacheWorkspaceMapperProvider = GenerateCacheableSchemesWorkspaceMapperProvider(
            workspaceMapperProvider: workspaceMapperProvider,
            includedTargets: includedTargets ?? []
        )
        let graphMapperProvider = GraphMapperProviderFactory().cacheProvider(includedTargets: includedTargets)
        return Generator(
            projectMapperProvider: projectMapperProvider,
            graphMapperProvider: graphMapperProvider,
            workspaceMapperProvider: cacheWorkspaceMapperProvider,
            manifestLoaderFactory: ManifestLoaderFactory()
        )
    }
}

protocol CacheControlling {
    /// Caches the cacheable targets that are part of the workspace or project at the given path.
    /// - Parameters:
    ///   - path: Path to the directory that contains a workspace or a project.
    ///   - cacheProfile: The caching profile.
    ///   - includedTargets: If present, a list of the targets and their dependencies to cache.
    ///   - dependenciesOnly: If true, the targets passed in the `targets` parameter are not cached, but only their dependencies
    func cache(path: AbsolutePath, cacheProfile: TuistGraph.Cache.Profile, includedTargets: Set<String>, dependenciesOnly: Bool) throws
}

final class CacheController: CacheControlling {
    /// Project generator provider.
    let projectGeneratorProvider: CacheControllerProjectGeneratorProviding

    /// Utility to build the (xc)frameworks.
    private let artifactBuilder: CacheArtifactBuilding

    private let bundleArtifactBuilder: CacheArtifactBuilding

    /// Cache graph content hasher.
    private let cacheGraphContentHasher: CacheGraphContentHashing

    /// Cache.
    private let cache: CacheStoring

    /// Cache graph linter.
    private let cacheGraphLinter: CacheGraphLinting

    convenience init(cache: CacheStoring,
                     artifactBuilder: CacheArtifactBuilding,
                     bundleArtifactBuilder: CacheArtifactBuilding,
                     contentHasher: ContentHashing)
    {
        self.init(
            cache: cache,
            artifactBuilder: artifactBuilder,
            bundleArtifactBuilder: bundleArtifactBuilder,
            projectGeneratorProvider: CacheControllerProjectGeneratorProvider(contentHasher: contentHasher),
            cacheGraphContentHasher: CacheGraphContentHasher(contentHasher: contentHasher),
            cacheGraphLinter: CacheGraphLinter()
        )
    }

    init(cache: CacheStoring,
         artifactBuilder: CacheArtifactBuilding,
         bundleArtifactBuilder: CacheArtifactBuilding,
         projectGeneratorProvider: CacheControllerProjectGeneratorProviding,
         cacheGraphContentHasher: CacheGraphContentHashing,
         cacheGraphLinter: CacheGraphLinting)
    {
        self.cache = cache
        self.projectGeneratorProvider = projectGeneratorProvider
        self.artifactBuilder = artifactBuilder
        self.bundleArtifactBuilder = bundleArtifactBuilder
        self.cacheGraphContentHasher = cacheGraphContentHasher
        self.cacheGraphLinter = cacheGraphLinter
    }

    func cache(path: AbsolutePath, cacheProfile: TuistGraph.Cache.Profile, includedTargets: Set<String>, dependenciesOnly: Bool) throws {
        let generator = projectGeneratorProvider.generator(includedTargets: includedTargets.isEmpty ? nil : Set(includedTargets))
        let (_, graph) = try generator.generateWithGraph(path: path, projectOnly: false)

        // Lint
        cacheGraphLinter.lint(graph: graph)

        // Hash
        logger.notice("Hashing cacheable targets")

        let hashesByTargetToBeCached = try makeHashesByTargetToBeCached(
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

        let updatedGenerator = projectGeneratorProvider.generator(includedTargets: Set(hashesByTargetToBeCached.map { $0.0.target.name }))

        let (projectPath, updatedGraph) = try updatedGenerator.generateWithGraph(path: path, projectOnly: false)

        logger.notice("Building cacheable targets")

        try archive(updatedGraph, projectPath: projectPath, cacheProfile: cacheProfile, hashesByTargetToBeCached)

        logger.notice("All cacheable targets have been cached successfully as \(artifactBuilder.cacheOutputType.description)s", metadata: .success)
    }

    private func archive(
        _ graph: Graph,
        projectPath: AbsolutePath,
        cacheProfile: TuistGraph.Cache.Profile,
        _ hashesByCacheableTarget: [(GraphTarget, String)]
    ) throws {
        let binariesSchemes = graph.workspace.schemes
            .filter { $0.name.contains(Constants.AutogeneratedScheme.binariesSchemeNamePrefix) }
            .filter { !($0.buildAction?.targets ?? []).isEmpty }
        let bundlesSchemes = graph.workspace.schemes
            .filter { $0.name.contains(Constants.AutogeneratedScheme.bundlesSchemeNamePrefix) }
            .filter { !($0.buildAction?.targets ?? []).isEmpty }

        try FileHandler.shared.inTemporaryDirectory { outputDirectory in
            for scheme in binariesSchemes {
                let outputDirectory = outputDirectory.appending(component: scheme.name)
                try FileHandler.shared.createFolder(outputDirectory)
                try artifactBuilder.build(
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
                try bundleArtifactBuilder.build(
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
            try hashesByCacheableTarget.forEach(context: .concurrent) { target, hash in
                let isBinary = target.target.product.isFramework
                let suffix = "\(isBinary ? Constants.AutogeneratedScheme.binariesSchemeNamePrefix : Constants.AutogeneratedScheme.bundlesSchemeNamePrefix)-\(target.target.platform.caseValue)"

                let productNameWithExtension = target.target.productName
                _ = try cache.store(
                    name: target.target.name,
                    hash: hash,
                    paths: FileHandler.shared.glob(outputDirectory.appending(component: suffix), glob: "\(productNameWithExtension).*")
                ).toBlocking().last()
            }
        }
    }

    func makeHashesByTargetToBeCached(
        for graph: Graph,
        cacheProfile: TuistGraph.Cache.Profile,
        cacheOutputType: CacheOutputType,
        includedTargets: Set<String>,
        dependenciesOnly: Bool
    ) throws -> [(GraphTarget, String)] {
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

        return try graph.compactMap(context: .concurrent) { target throws -> (GraphTarget, String)? in
            guard
                let hash = hashesByCacheableTarget[target],
                // if cache already exists, no need to build
                try !self.cache.exists(name: target.target.name, hash: hash).toBlocking().single()
            else {
                return nil
            }

            return (target, hash)
        }
        .reversed()
    }
}
