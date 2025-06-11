import Foundation
import Path
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

    func run(xcodeprojPath: AbsolutePath) async throws {
        let sortedTargets = try await targetsExtractor.targetsSortedByDependencies(xcodeprojPath: xcodeprojPath)
        let sortedTargetsJson = try makeJson(from: sortedTargets)
        Logger.current.notice("\(sortedTargetsJson)")
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
