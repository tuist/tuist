import Foundation
import Path
import TuistCache
import TuistCore
import TuistHasher
import TuistLoader
import TuistSupport
import XcodeGraph
import XcodeGraphMapper

enum HashCacheCommandServiceError: LocalizedError, Equatable {
    case generatedProjectNotFound(AbsolutePath)

    var errorDescription: String? {
        switch self {
        case let .generatedProjectNotFound(path):
            return "We couldn't find a generated project at \(path.pathString). Binary caching only works with generated projects."
        }
    }
}

final class HashCacheCommandService {
    private let generatorFactory: GeneratorFactorying
    private let cacheGraphContentHasher: CacheGraphContentHashing
    private let clock: Clock
    private let configLoader: ConfigLoading
    private let manifestLoader: ManifestLoading
    private let manifestGraphLoader: ManifestGraphLoading

    convenience init(
        contentHasher: ContentHashing = CachedContentHasher(),
        generatorFactory: GeneratorFactorying = GeneratorFactory()
    ) {
        let manifestLoader = ManifestLoaderFactory()
            .createManifestLoader()
        let manifestGraphLoader = ManifestGraphLoader(
            manifestLoader: manifestLoader,
            workspaceMapper: SequentialWorkspaceMapper(mappers: []),
            graphMapper: SequentialGraphMapper([])
        )
        self.init(
            generatorFactory: generatorFactory,
            cacheGraphContentHasher: CacheGraphContentHasher(contentHasher: contentHasher),
            clock: WallClock(),
            configLoader: ConfigLoader(manifestLoader: ManifestLoader()),
            manifestLoader: manifestLoader,
            manifestGraphLoader: manifestGraphLoader
        )
    }

    init(
        generatorFactory: GeneratorFactorying,
        cacheGraphContentHasher: CacheGraphContentHashing,
        clock: Clock,
        configLoader: ConfigLoading,
        manifestLoader: ManifestLoading,
        manifestGraphLoader: ManifestGraphLoading
    ) {
        self.generatorFactory = generatorFactory
        self.cacheGraphContentHasher = cacheGraphContentHasher
        self.clock = clock
        self.configLoader = configLoader
        self.manifestLoader = manifestLoader
        self.manifestGraphLoader = manifestGraphLoader
    }

    private func absolutePath(_ path: String?) throws -> AbsolutePath {
        if let path {
            return try AbsolutePath(validating: path, relativeTo: FileHandler.shared.currentPath)
        } else {
            return FileHandler.shared.currentPath
        }
    }

    func run(
        path: String?,
        configuration: String?
    ) async throws {
        let absolutePath = try absolutePath(path)

        let graph: XcodeGraph.Graph
        let defaultConfiguration: String?

        if try await manifestLoader.hasRootManifest(at: absolutePath) {
            let config = try await configLoader.loadConfig(path: absolutePath)
            let generator = generatorFactory.defaultGenerator(config: config, includedTargets: [])
            graph = try await generator.load(
                path: absolutePath,
                options: config.project.generatedProject?.generationOptions
            )
            defaultConfiguration = config.project.generatedProject?.generationOptions.defaultConfiguration
        } else {
            defaultConfiguration = nil
            throw HashCacheCommandServiceError.generatedProjectNotFound(absolutePath)
        }

        let hashes = try await cacheGraphContentHasher.contentHashes(
            for: graph,
            configuration: configuration,
            defaultConfiguration: defaultConfiguration,
            excludedTargets: [],
            destination: nil
        )

        let sortedHashes = hashes.sorted { $0.key.target.name < $1.key.target.name }

        if sortedHashes.isEmpty {
            AlertController.current.warning(.alert("The project contains no hashable targets."))
        } else {
            for (target, hash) in sortedHashes {
                Logger.current.info("\(target.target.name) - \(hash)")
            }
        }
    }
}
