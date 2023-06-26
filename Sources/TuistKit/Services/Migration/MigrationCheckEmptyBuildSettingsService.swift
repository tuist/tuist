import Foundation
import TSCBasic
import TuistMigration
import TuistSupport

public class MigrationCheckEmptyBuildSettingsService {
    // MARK: - Attributes

    private let emptyBuildSettingsChecker: EmptyBuildSettingsChecking

    // MARK: - Init
    
    public convenience init() {
        self.init(emptyBuildSettingsChecker: EmptyBuildSettingsChecker())
    }

    init(emptyBuildSettingsChecker: EmptyBuildSettingsChecking) {
        self.emptyBuildSettingsChecker = emptyBuildSettingsChecker
    }

    // MARK: - Internal

    public func run(xcodeprojPath: AbsolutePath, target: String?) throws {
        try emptyBuildSettingsChecker.check(xcodeprojPath: xcodeprojPath, targetName: target)
    }
}
