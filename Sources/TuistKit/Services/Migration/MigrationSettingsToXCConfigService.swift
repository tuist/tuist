import Foundation
import TSCBasic
import TuistMigration
import TuistSupport

class MigrationSettingsToXCConfigService {
    // MARK: - Attributes

    private let settingsToXCConfigExtractor: SettingsToXCConfigExtracting

    // MARK: - Init

    init(settingsToXCConfigExtractor: SettingsToXCConfigExtracting = SettingsToXCConfigExtractor()) {
        self.settingsToXCConfigExtractor = settingsToXCConfigExtractor
    }

    // MARK: - Internal

    func run(xcodeprojPath: String, xcconfigPath: String, target: String?) throws {
        try settingsToXCConfigExtractor.extract(
            xcodeprojPath: try AbsolutePath(validating: xcodeprojPath, relativeTo: FileHandler.shared.currentPath),
            targetName: target,
            xcconfigPath: try AbsolutePath(validating: xcconfigPath, relativeTo: FileHandler.shared.currentPath)
        )
    }
}
