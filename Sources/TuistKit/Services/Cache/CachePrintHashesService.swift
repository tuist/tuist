import Foundation
import TSCBasic
import TuistAutomation
import TuistCache
import TuistCore
import TuistLoader
import TuistSupport

final class CachePrintHashesService {
    /// Project generator
    let generator: Generating

    let graphContentHasher: GraphContentHashing
    private let clock: Clock
    private let generatorModelLoader: GeneratorModelLoading

    convenience init(contentHasher: ContentHashing = CacheContentHasher()) {
        self.init(generator: Generator(contentHasher: contentHasher),
                  graphContentHasher: GraphContentHasher(contentHasher: contentHasher),
                  clock: WallClock(),
                  generatorModelLoader: GeneratorModelLoader())
    }

    init(generator: Generating, graphContentHasher: GraphContentHashing, clock: Clock, generatorModelLoader: GeneratorModelLoading) {
        self.generator = generator
        self.graphContentHasher = graphContentHasher
        self.clock = clock
        self.generatorModelLoader = generatorModelLoader
    }

    func run(path: AbsolutePath, xcframeworks: Bool, profile: String?) throws {
        let timer = clock.startTimer()

        let graph = try generator.load(path: path)
        let config = try generatorModelLoader.loadConfig(at: path)
        let cacheOutputType: CacheOutputType = xcframeworks ? .xcframework : .framework
        let cacheProfile = try CacheProfileResolver().resolveCacheProfile(named: profile, from: config)
        let hashes = try graphContentHasher.contentHashes(for: graph, cacheProfile: cacheProfile, cacheOutputType: cacheOutputType)
        let duration = timer.stop()
        let time = String(format: "%.3f", duration)
        guard hashes.count > 0 else {
            logger.notice("No cacheable targets were found")
            return
        }
        let sortedHashes = hashes.sorted { $0.key.name < $1.key.name }
        for (target, hash) in sortedHashes {
            logger.info("\(target.name) - \(hash)")
        }
        logger.notice("Total time taken: \(time)s")
    }
}
