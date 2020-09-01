import Foundation
import TSCBasic
import TuistMigration
import TuistSupport

final class MigrationTargetsByDependenciesService {
    // MARK: - Attributes

    private let targetsExtractor: TargetsExtracting

    // MARK: - Init

    init(targetsExtractor: TargetsExtracting = TargetsExtractor()) {
        self.targetsExtractor = targetsExtractor
    }

    // MARK: - Internal

    func run(xcodeprojPath: AbsolutePath) throws {
        let sortedTargets = try targetsExtractor.targetsSortedByDependencies(xcodeprojPath: xcodeprojPath)
        logger.info("Targets sorted by number of dependencies ascending:\n")
        sortedTargets.forEach {
            logger.info("\($0.targetName) - dependencies count: \($0.dependenciesCount)")
        }
    }
}
