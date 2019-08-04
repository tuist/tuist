import Foundation
import ProjectDescription
import TuistCore

protocol ManifestLinting {
    func lint(project: Project) -> [LintingIssue]
}

class ManifestLinter: ManifestLinting {
    func lint(project: Project) -> [LintingIssue] {
        var issues = [LintingIssue]()

        if let settings = project.settings {
            issues.append(contentsOf: lint(settings: settings, declarationLocation: project.name))
        }

        issues.append(contentsOf: project.targets.flatMap(lint))

        return issues
    }

    private func lint(target: Target) -> [LintingIssue] {
        var issues = [LintingIssue]()

        if let settings = target.settings {
            issues.append(contentsOf: lint(settings: settings, declarationLocation: target.name))
        }

        return issues
    }

    private func lint(settings: Settings, declarationLocation: String) -> [LintingIssue] {
        let configurationNames = settings.configurations.map(\.name)

        return configurationNames.spm_findDuplicates().map {
            LintingIssue(reason: "The configuration '\($0)' is declared multiple times within '\(declarationLocation)' settings. The last declared configuration will be used.", severity: .warning)
        }
    }
}
