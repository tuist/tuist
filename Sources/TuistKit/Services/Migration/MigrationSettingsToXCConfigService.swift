import Foundation
import TSCBasic
import TuistMigration
import TuistSupport

public class MigrationSettingsToXCConfigService {
    // MARK: - Attributes

    private let settingsToXCConfigExtractor: SettingsToXCConfigExtracting

    // MARK: - Init
    
    public convenience init() {
        self.init(settingsToXCConfigExtractor: SettingsToXCConfigExtractor())
    }

    init(settingsToXCConfigExtractor: SettingsToXCConfigExtracting) {
        self.settingsToXCConfigExtractor = settingsToXCConfigExtractor
    }

    // MARK: - Internal

    public func run(xcodeprojPath: String, xcconfigPath: String, target: String?) throws {
        try settingsToXCConfigExtractor.extract(
            xcodeprojPath: try AbsolutePath(validating: xcodeprojPath, relativeTo: FileHandler.shared.currentPath),
            targetName: target,
            xcconfigPath: try AbsolutePath(validating: xcconfigPath, relativeTo: FileHandler.shared.currentPath)
        )
    }
}
