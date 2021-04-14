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
            xcodeprojPath: AbsolutePath(xcodeprojPath, relativeTo: FileHandler.shared.currentPath),
            targetName: target,
            xcconfigPath: AbsolutePath(xcconfigPath, relativeTo: FileHandler.shared.currentPath)
        )
    }
}
