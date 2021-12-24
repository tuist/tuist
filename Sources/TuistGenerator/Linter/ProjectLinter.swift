import Foundation
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport

protocol ProjectLinting: AnyObject {
    func lint(_ project: Project) -> [LintingIssue]
}

class ProjectLinter: ProjectLinting {
    // MARK: - Attributes

    let targetLinter: TargetLinting
    let settingsLinter: SettingsLinting
    let schemeLinter: SchemeLinting
    let packageLinter: PackageLinting

    // MARK: - Init

    init(targetLinter: TargetLinting = TargetLinter(),
         settingsLinter: SettingsLinting = SettingsLinter(),
         schemeLinter: SchemeLinting = SchemeLinter(),
         packageLinter: PackageLinting = PackageLinter())
    {
        self.targetLinter = targetLinter
        self.settingsLinter = settingsLinter
        self.schemeLinter = schemeLinter
        self.packageLinter = packageLinter
    }

    // MARK: - ProjectLinting

    func lint(_ project: Project) -> [LintingIssue] {
        var issues: [LintingIssue] = []
        issues.append(contentsOf: lintTargets(project: project))
        issues.append(contentsOf: settingsLinter.lint(project: project))
        issues.append(contentsOf: schemeLinter.lint(project: project))
        issues.append(contentsOf: lintPackages(project: project))
        issues.append(contentsOf: lintOptions(project: project))
        return issues
    }

    // MARK: - Fileprivate

    private func lintPackages(project: Project) -> [LintingIssue] {
        project.packages.flatMap(packageLinter.lint)
    }

    private func lintTargets(project: Project) -> [LintingIssue] {
        var issues: [LintingIssue] = []
        issues.append(contentsOf: project.targets.flatMap(targetLinter.lint))
        issues.append(contentsOf: lintNotDuplicatedTargets(project: project))
        return issues
    }

    private func lintNotDuplicatedTargets(project: Project) -> [LintingIssue] {
        var issues: [LintingIssue] = []
        let duplicatedTargets = project.targets.map(\.name)
            .reduce(into: [String: Int]()) { $0[$1] = ($0[$1] ?? 0) + 1 }
            .filter { $0.value > 1 }
            .keys
        if !duplicatedTargets.isEmpty {
            let issue = LintingIssue(
                reason: "Targets \(duplicatedTargets.joined(separator: ", ")) from project at \(project.path.pathString) have duplicates.",
                severity: .error
            )
            issues.append(issue)
        }
        return issues
    }

    private func lintOptions(project: Project) -> [LintingIssue] {
        var issues: [LintingIssue] = []
        issues.append(contentsOf: lintNotDuplicatedOptions(project: project))
        return issues
    }

    private func lintNotDuplicatedOptions(project: Project) -> [LintingIssue] {
        var issues: [LintingIssue] = []
        let duplicatedOptions = project.options
            .reduce(into: [ProjectOption: Int]()) { $0[$1, default: 0] += 1 }
            .filter { $0.value > 1 }
            .keys
        if !duplicatedOptions.isEmpty {
            let optionsNames = duplicatedOptions.map(\.name)

            let issue = LintingIssue(
                reason: "Options \"\(optionsNames.joined(separator: ", "))\" from project at \(project.path.pathString) have duplicates.",
                severity: .error
            )
            issues.append(issue)
        }
        return issues
    }
}
