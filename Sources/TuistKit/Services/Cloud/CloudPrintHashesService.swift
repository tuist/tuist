import Foundation
import TSCBasic
import TuistAutomation
import TuistCache
import TuistCore
import TuistSupport

final class CloudPrintHashesService {
    /// Project generator
    let projectGenerator: ProjectGenerating

    let graphContentHasher: GraphContentHashing
    private let clock: Clock

    init(projectGenerator: ProjectGenerating = ProjectGenerator(),
         graphContentHasher: GraphContentHashing = GraphContentHasher(),
         clock: Clock = WallClock()) {
        self.projectGenerator = projectGenerator
        self.graphContentHasher = graphContentHasher
        self.clock = clock
    }

    func run(path: AbsolutePath) throws -> TimeInterval {
        let timer = clock.startTimer()

        let graph = try projectGenerator.load(path: path)
        let hashes = try graphContentHasher.contentHashes(for: graph)
        let duration = timer.stop()
        let time = String(format: "%.3f", duration)

        for (target, hash) in hashes {
            logger.info("\(target.name) - \(hash)")
        }
        logger.notice("Total time taken: \(time)s")
        return duration
    }
}
