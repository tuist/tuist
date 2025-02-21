import Foundation
import Path
import ServiceContextModule
import TuistCache
import TuistCore
import TuistHasher
import TuistLoader
import TuistSupport

final class CachePrintHashesService {
    private let generatorFactory: GeneratorFactorying
    private let cacheGraphContentHasher: CacheGraphContentHashing
    private let clock: Clock
    private let configLoader: ConfigLoading

    convenience init(
        contentHasher: ContentHashing = CachedContentHasher(),
        generatorFactory: GeneratorFactorying
    ) {
        self.init(
            generatorFactory: generatorFactory,
            cacheGraphContentHasher: CacheGraphContentHasher(contentHasher: contentHasher),
            clock: WallClock(),
            configLoader: ConfigLoader(manifestLoader: ManifestLoader())
        )
    }

    init(
        generatorFactory: GeneratorFactorying,
        cacheGraphContentHasher: CacheGraphContentHashing,
        clock: Clock,
        configLoader: ConfigLoading
    ) {
        self.generatorFactory = generatorFactory
        self.cacheGraphContentHasher = cacheGraphContentHasher
        self.clock = clock
        self.configLoader = configLoader
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
        let timer = clock.startTimer()
        let config = try await configLoader.loadConfig(path: absolutePath)
        let generator = generatorFactory.defaultGenerator(config: config, sources: [])
        let graph = try await generator.load(path: absolutePath)
        let hashes = try await cacheGraphContentHasher.contentHashes(
            for: graph,
            configuration: configuration,
            config: config,
            excludedTargets: []
        )
        let duration = timer.stop()
        let time = String(format: "%.3f", duration)
        guard hashes.count > 0 else {
            ServiceContext.current?.logger?.notice("No cacheable targets were found")
            return
        }
        let sortedHashes = hashes.sorted { $0.key.target.name < $1.key.target.name }
        for (target, hash) in sortedHashes {
            ServiceContext.current?.logger?.info("\(target.target.name) - \(hash)")
        }
        ServiceContext.current?.logger?.notice("Total time taken: \(time)s")
    }
}
