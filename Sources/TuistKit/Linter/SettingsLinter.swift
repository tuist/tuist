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

    fileprivate func lintConfigFilesExist(settings: Settings) -> [LintingIssue] {
        var issues: [LintingIssue] = []

        let lintPath: (AbsolutePath) -> Void = { path in
            if !self.fileHandler.exists(path) {
                issues.append(LintingIssue(reason: "Configuration file not found at path \(path.asString)", severity: .error))
            }
        }

        for case .some(let xcconfigFile) in settings.configurations.map(\.xcconfig) {
            lintPath(xcconfigFile)
        }

        return issues
    }
}
