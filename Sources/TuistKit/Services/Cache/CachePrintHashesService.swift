import Foundation
import TSCBasic
import TuistAutomation
import TuistCache
import TuistCore
import TuistSupport

final class CachePrintHashesService {
    /// Project generator
    let projectGenerator: ProjectGenerating

    let graphContentHasher: GraphContentHashing
    private let clock: Clock

    init(projectGenerator: ProjectGenerating = ProjectGenerator(),
         graphContentHasher: GraphContentHashing = GraphContentHasher(),
         clock: Clock = WallClock())
    {
        self.projectGenerator = projectGenerator
        self.graphContentHasher = graphContentHasher
        self.clock = clock
    }

    func run(path: AbsolutePath) throws {
        let timer = clock.startTimer()

        let graph = try projectGenerator.load(path: path)
        let hashes = try graphContentHasher.contentHashes(for: graph)
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
