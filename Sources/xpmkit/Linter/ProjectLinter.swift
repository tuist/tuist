import Basic
import Foundation
import xpmcore

/// Project linting protocol.
protocol ProjectLinting: AnyObject {
    func lint(_ project: Project) -> [LintingIssue]
}

/// Lints the format of the project.
class ProjectLinter: ProjectLinting {

    // MARK: - Attributes

    /// Target linter.
    let targetLinter: TargetLinting

    /// Initialize the linter with its attributes.
    ///
    /// - Parameter targetLinter: target linter.
    init(targetLinter: TargetLinting = TargetLinter()) {
        self.targetLinter = targetLinter
    }

    func lint(_ project: Project) -> [LintingIssue] {
        var issues: [LintingIssue] = []
        issues.append(contentsOf: lintTargets(project: project))
        return issues
    }

    fileprivate func lintTargets(project: Project) -> [LintingIssue] {
        var issues: [LintingIssue] = []
        issues.append(contentsOf: project.targets.flatMap(targetLinter.lint))
        issues.append(contentsOf: lintNotDuplicatedTargets(project: project))
        return issues
    }

    fileprivate func lintNotDuplicatedTargets(project: Project) -> [LintingIssue] {
        var issues: [LintingIssue] = []
        let duplicatedTargets = project.targets.map({ $0.name })
            .reduce(into: [String: Int]()) { $0[$1] = ($0[$1] ?? 0) + 1 }
            .filter({ $0.value > 1 })
            .keys
        if duplicatedTargets.count != 0 {
            let issue = LintingIssue(reason: "Targets \(duplicatedTargets.joined(separator: ", ")) from project at \(project.path.asString) have duplicates.",
                                     severity: .error)
            issues.append(issue)
        }
        return issues
    }
}
