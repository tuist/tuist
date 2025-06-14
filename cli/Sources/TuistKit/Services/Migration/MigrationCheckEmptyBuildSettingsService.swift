import Foundation
import Path
import TuistMigration
import TuistSupport

class MigrationCheckEmptyBuildSettingsService {
    // MARK: - Attributes

    private let emptyBuildSettingsChecker: EmptyBuildSettingsChecking

    // MARK: - Init

    init(emptyBuildSettingsChecker: EmptyBuildSettingsChecking = EmptyBuildSettingsChecker()) {
        self.emptyBuildSettingsChecker = emptyBuildSettingsChecker
    }

    // MARK: - Internal

    func run(xcodeprojPath: AbsolutePath, target: String?) async throws {
        try await emptyBuildSettingsChecker.check(xcodeprojPath: xcodeprojPath, targetName: target)
    }
}
