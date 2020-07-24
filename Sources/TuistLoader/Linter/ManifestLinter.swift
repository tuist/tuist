import Foundation
import ProjectDescription
import TuistCore
import TuistSupport

public protocol ManifestLinting {
    func lint(project: ProjectDescription.Project) -> [LintingIssue]
}

public class AnyManifestLinter: ManifestLinting {
    let lint: ((ProjectDescription.Project) -> [LintingIssue])?

    public init(lint: ((ProjectDescription.Project) -> [LintingIssue])? = nil) {
        self.lint = lint
    }

    public func lint(project: ProjectDescription.Project) -> [LintingIssue] {
        if let lint = self.lint {
            return lint(project)
        } else {
            return []
        }
    }
}

public class ManifestLinter: ManifestLinting {
    public init() {}

    public func lint(project: ProjectDescription.Project) -> [LintingIssue] {
        var issues = [LintingIssue]()

        if let settings = project.settings {
            issues.append(contentsOf: lint(settings: settings, declarationLocation: project.name))
        }

        issues.append(contentsOf: project.targets.flatMap(lint))

        return issues
    }

    private func lint(target: ProjectDescription.Target) -> [LintingIssue] {
        var issues = [LintingIssue]()

        if let settings = target.settings {
            issues.append(contentsOf: lint(settings: settings, declarationLocation: target.name))
        }

        issues.append(contentsOf: lint(coredataModels: target.coreDataModels, declarationLocation: target.name))

        return issues
    }

    private func lint(settings: ProjectDescription.Settings, declarationLocation: String) -> [LintingIssue] {
        let configurationNames = settings.configurations.map(\.name)

        return configurationNames.spm_findDuplicates().map {
            LintingIssue(reason: "The configuration '\($0)' is declared multiple times within '\(declarationLocation)' settings. The last declared configuration will be used.", severity: .warning)
        }
    }

    private func lint(coredataModels: [ProjectDescription.CoreDataModel], declarationLocation: String) -> [LintingIssue] {

        let currentVersions = coredataModels.compactMap(\.currentVersion)

        return currentVersions.map {
            LintingIssue(reason: "The current core data model version '\(String(describing: $0))' will be infered automatically in '\(declarationLocation)' settings. It is not need it to set the current version anymore.", severity: .warning)
        }
    }

}
