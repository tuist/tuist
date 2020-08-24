import Foundation
import TSCBasic
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

    func run(xcodeprojPath: String, target: String?) throws {
        try emptyBuildSettingsChecker.check(xcodeprojPath: AbsolutePath(xcodeprojPath), targetName: target)
    }
}
