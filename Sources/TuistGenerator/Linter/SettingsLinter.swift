import Basic
import Foundation
import TuistCore

protocol SettingsLinting: AnyObject {
    func lint(settings: Settings) -> [LintingIssue]
}

final class SettingsLinter: SettingsLinting {
    // MARK: - Attributes

    let fileHandler: FileHandling

    // MARK: - Init

    init(fileHandler: FileHandling = FileHandler()) {
        self.fileHandler = fileHandler
    }

    // MARK: - SettingsLinting

    func lint(settings: Settings) -> [LintingIssue] {
        var issues: [LintingIssue] = []
        issues.append(contentsOf: lintConfigFilesExist(settings: settings))
        return issues
    }

    // MARK: - Fileprivate

    private func lintConfigFilesExist(settings: Settings) -> [LintingIssue] {
        var issues: [LintingIssue] = []

        let lintPath: (AbsolutePath) -> Void = { path in
            if !self.fileHandler.exists(path) {
                issues.append(LintingIssue(reason: "Configuration file not found at path \(path.pathString)", severity: .error))
            }
        }

        settings.xcconfigs().forEach { configFilePath in
            lintPath(configFilePath)
        }

        return issues
    }
}
