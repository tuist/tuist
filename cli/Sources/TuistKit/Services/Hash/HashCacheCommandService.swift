import Foundation
import Path
import TuistAlert
import TuistCache
import TuistConfigLoader
import TuistCore
import TuistExtension
import TuistHasher
import TuistLoader
import TuistLogging
import TuistSupport
import XcodeGraph
#if canImport(TuistCacheEE)
    import TuistCacheEE
#endif

enum HashCacheCommandServiceError: LocalizedError, Equatable {
    case generatedProjectNotFound(AbsolutePath)

    var errorDescription: String? {
        switch self {
        case let .generatedProjectNotFound(path):
            return "We couldn't find a generated project at \(path.pathString). Binary caching only works with generated projects."
        }
    }
}

public final class HashCacheCommandService: HashCacheServicing {
    #if canImport(TuistCacheEE)
        private let generatorFactory: CacheGeneratorFactorying
    #else
        private let generatorFactory: GeneratorFactorying
    #endif
    private let cacheGraphContentHasher: CacheGraphContentHashing
    private let configLoader: ConfigLoading
    private let manifestLoader: ManifestLoading

    public convenience init(
        contentHasher: ContentHashing = CachedContentHasher()
    ) {
        #if canImport(TuistCacheEE)
            let generatorFactory = CacheGeneratorFactory(contentHasher: contentHasher)
        #else
            let generatorFactory = GeneratorFactory()
        #endif
        let manifestLoader = ManifestLoader.current
        self.init(
            generatorFactory: generatorFactory,
            cacheGraphContentHasher: CacheGraphContentHasher(contentHasher: contentHasher),
            configLoader: ConfigLoader(),
            manifestLoader: manifestLoader
        )
    }

    #if canImport(TuistCacheEE)
        init(
            generatorFactory: CacheGeneratorFactorying,
            cacheGraphContentHasher: CacheGraphContentHashing,
            configLoader: ConfigLoading,
            manifestLoader: ManifestLoading
        ) {
            self.generatorFactory = generatorFactory
            self.cacheGraphContentHasher = cacheGraphContentHasher
            self.configLoader = configLoader
            self.manifestLoader = manifestLoader
        }
    #else
        init(
            generatorFactory: GeneratorFactorying,
            cacheGraphContentHasher: CacheGraphContentHashing,
            configLoader: ConfigLoading,
            manifestLoader: ManifestLoading
        ) {
            self.generatorFactory = generatorFactory
            self.cacheGraphContentHasher = cacheGraphContentHasher
            self.configLoader = configLoader
            self.manifestLoader = manifestLoader
        }
    #endif

    private func absolutePath(_ path: String?) throws -> AbsolutePath {
        if let path {
            return try AbsolutePath(validating: path, relativeTo: FileHandler.shared.currentPath)
        } else {
            return FileHandler.shared.currentPath
        }
    }

    public func run(
        path: String?,
        configuration: String?
    ) async throws {
        let absolutePath = try absolutePath(path)

        let graph: XcodeGraph.Graph
        let defaultConfiguration: String?

        if try await manifestLoader.hasRootManifest(at: absolutePath) {
            let config = try await configLoader.loadConfig(path: absolutePath)

            #if canImport(TuistCacheEE)
                let generator = generatorFactory.binaryCacheWarmingPreload(
                    config: config,
                    targetsToBinaryCache: []
                )
            #else
                let generator = generatorFactory.defaultGenerator(config: config, includedTargets: [])
            #endif
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
            for (target, targetContentHash) in sortedHashes {
                Logger.current.info("\(target.target.name) - \(targetContentHash.hash)")
            }
        }
    }
}
