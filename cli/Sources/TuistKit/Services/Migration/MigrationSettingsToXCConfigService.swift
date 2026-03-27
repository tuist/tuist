import Foundation
import Path
import TuistEnvironment
import TuistMigration

struct MigrationSettingsToXCConfigService {
    // MARK: - Attributes

    private let settingsToXCConfigExtractor: SettingsToXCConfigExtracting

    // MARK: - Init

    init(settingsToXCConfigExtractor: SettingsToXCConfigExtracting = SettingsToXCConfigExtractor()) {
        self.settingsToXCConfigExtractor = settingsToXCConfigExtractor
    }

    // MARK: - Internal

    func run(xcodeprojPath: String, xcconfigPath: String, target: String?) async throws {
        let cwd = try await Environment.current.currentWorkingDirectory()
        try await settingsToXCConfigExtractor.extract(
            xcodeprojPath: try AbsolutePath(validating: xcodeprojPath, relativeTo: cwd),
            targetName: target,
            xcconfigPath: try AbsolutePath(validating: xcconfigPath, relativeTo: cwd)
        )
    }
}
