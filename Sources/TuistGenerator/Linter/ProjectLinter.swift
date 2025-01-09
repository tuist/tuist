import Foundation
import TuistCore
import TuistSupport
import XcodeGraph

protocol ProjectLinting: AnyObject {
    func lint(_ project: Project) async throws -> [LintingIssue]
}

class ProjectLinter: ProjectLinting {
    // MARK: - Attributes

    let targetLinter: TargetLinting
    let settingsLinter: SettingsLinting
    let schemeLinter: SchemeLinting
    let packageLinter: PackageLinting

    // MARK: - Init

    init(
        targetLinter: TargetLinting = TargetLinter(),
        settingsLinter: SettingsLinting = SettingsLinter(),
        schemeLinter: SchemeLinting = SchemeLinter(),
        packageLinter: PackageLinting = PackageLinter()
    ) {
        self.targetLinter = targetLinter
        self.settingsLinter = settingsLinter
        self.schemeLinter = schemeLinter
        self.packageLinter = packageLinter
    }

    // MARK: - ProjectLinting

    func lint(_ project: Project) async throws -> [LintingIssue] {
        var issues: [LintingIssue] = []
        try await issues.append(contentsOf: lintTargets(project: project))
        try await issues.append(contentsOf: settingsLinter.lint(project: project))
        try await issues.append(contentsOf: schemeLinter.lint(project: project))
        try await issues.append(contentsOf: lintPackages(project: project))
        return issues
    }

    // MARK: - Fileprivate

    private func lintPackages(project: Project) async throws -> [LintingIssue] {
        try await project.packages.concurrentFlatMap(packageLinter.lint)
    }

    private func lintTargets(project: Project) async throws -> [LintingIssue] {
        return try await project.targets.values
            .map { $0 }
            .concurrentFlatMap { target in
                try await self.targetLinter.lint(target: target, options: project.options)
            }
    }
}
