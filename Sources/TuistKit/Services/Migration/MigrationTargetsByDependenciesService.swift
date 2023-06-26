import Foundation
import TSCBasic
import TuistMigration
import TuistSupport

public final class MigrationTargetsByDependenciesService {
    // MARK: - Attributes

    private let targetsExtractor: TargetsExtracting

    // MARK: - Init

    public convenience init() {
        self.init(targetsExtractor: TargetsExtractor())
    }

    init(targetsExtractor: TargetsExtracting) {
        self.targetsExtractor = targetsExtractor
    }

    // MARK: - Internal

    public func run(xcodeprojPath: AbsolutePath) throws {
        let sortedTargets = try targetsExtractor.targetsSortedByDependencies(xcodeprojPath: xcodeprojPath)
        let sortedTargetsJson = try makeJson(from: sortedTargets)
        logger.info("\(sortedTargetsJson)")
    }

    private func makeJson(from sortedTargets: [TargetDependencyCount]) throws -> String {
        let jsonEncoder = JSONEncoder()
        jsonEncoder.outputFormatting = .prettyPrinted
        let targetsData = try jsonEncoder.encode(sortedTargets)
        guard let jsonString = String(data: targetsData, encoding: .utf8) else {
            throw TargetsExtractorError.failedToEncode
        }
        return jsonString
    }
}
