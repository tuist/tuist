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
                return switch project.type {
                case .local:
                    // only do source file lint for local target, or for some external target like systemLibrary, it always raise
                    // warning
                    try await self.targetLinter.lint(target: target, options: project.options)
                        + self.lintHasSourceFiles(target: target)
                case .external:
                    try await self.targetLinter.lint(target: target, options: project.options)
                }
            }
    }

    private func lintHasSourceFiles(target: Target) -> [LintingIssue] {
        let supportsSources = target.supportsSources
        let sources = target.sources

        let hasNoSources = supportsSources && sources.isEmpty
        let hasNoDependencies = target.dependencies.isEmpty
        let hasNoScripts = target.scripts.isEmpty

        // macOS bundle targets can have source code, but it's optional
        if target.isExclusiveTo(.macOS), target.product == .bundle, hasNoSources {
            return []
        }

        if hasNoSources, hasNoDependencies, hasNoScripts {
            return [LintingIssue(reason: "The target \(target.name) doesn't contain source files.", severity: .warning)]
        } else if !supportsSources, !sources.isEmpty {
            return [LintingIssue(
                reason: "Target \(target.name) cannot contain sources. \(target.product) targets in one of these destinations doesn't support source files: \(target.destinations.map(\.rawValue).sorted().joined(separator: ", "))",
                severity: .error
            )]
        }

        return []
    }
}
