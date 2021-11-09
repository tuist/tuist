import Foundation
import TSCBasic
import TuistAutomation
import TuistCache
import TuistCore
import TuistLoader
import TuistSupport

final class CachePrintHashesService {
    private let generatorFactory: GeneratorFactorying
    private let cacheGraphContentHasher: CacheGraphContentHashing
    private let clock: Clock
    private let configLoader: ConfigLoading

    convenience init(contentHasher: ContentHashing = CacheContentHasher()) {
        self.init(
            generatorFactory: GeneratorFactory(),
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

    func run(path: AbsolutePath, xcframeworks: Bool, profile: String?) throws {
        let timer = clock.startTimer()
        let config = try configLoader.loadConfig(path: path)
        let generator = generatorFactory.default(config: config)
        let graph = try generator.load(path: path)
        let cacheOutputType: CacheOutputType = xcframeworks ? .xcframework : .framework
        let cacheProfile = try CacheProfileResolver().resolveCacheProfile(named: profile, from: config)
        let hashes = try cacheGraphContentHasher.contentHashes(
            for: graph,
            cacheProfile: cacheProfile,
            cacheOutputType: cacheOutputType,
            excludedTargets: []
        )
        let duration = timer.stop()
        let time = String(format: "%.3f", duration)
        guard hashes.count > 0 else {
            logger.notice("No cacheable targets were found")
            return
        }
        let sortedHashes = hashes.sorted { $0.key.target.name < $1.key.target.name }
        for (target, hash) in sortedHashes {
            logger.info("\(target.target.name) - \(hash)")
        }
        logger.notice("Total time taken: \(time)s")
    }
}
