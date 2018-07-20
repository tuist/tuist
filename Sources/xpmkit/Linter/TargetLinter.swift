import Foundation
import xpmcore

/// Target linting protocol.
protocol TargetLinting: AnyObject {
    /// It lints the given target.
    ///
    /// - Parameter target: target to be valdiated.
    /// - Throws: an error if the linting fails.
    func lint(target: Target) -> [LintingIssue]
}

class TargetLinter: TargetLinting {
    /// It lints the given target.
    ///
    /// - Parameter target: target to be valdiated.
    /// - Throws: an error if the linting fails.
    func lint(target: Target) -> [LintingIssue] {
        var issues: [LintingIssue] = []
        issues.append(contentsOf: lintHasSourceFiles(target: target))
        issues.append(contentsOf: lintOneSourcesPhase(target: target))
        issues.append(contentsOf: lintOneHeadersPhase(target: target))
        return issues
    }

    /// Lints that the target contains source files.
    ///
    /// - Parameter target: target to be validated.
    /// - Throws: an error if the target doesn't contain any sources.

    fileprivate func lintHasSourceFiles(target: Target) -> [LintingIssue] {
        let files = target.buildPhases.compactMap({ $0 as? SourcesBuildPhase })
            .flatMap({ $0.buildFiles })
            .flatMap({ $0.paths })
        var issues: [LintingIssue] = []
        if files.count == 0 {
            issues.append(LintingIssue(reason: "The target \(target.name) doesn't contain source files.", severity: .warning))
        }
        return issues
    }

    /// Verifies that the target has only one sources phase.
    ///
    /// - Parameter target: target to be linted.
    /// - Returns: a linting issue if the target has more than one source phase.
    fileprivate func lintOneSourcesPhase(target: Target) -> [LintingIssue] {
        let sourcesPhases = target.buildPhases
            .filter({ $0 is SourcesBuildPhase })
            .count
        if sourcesPhases <= 1 { return [] }
        return [LintingIssue(reason: "The target \(target.name) has more than one sources build phase.", severity: .error)]
    }

    /// Verifies that the target has only one headers phase.
    ///
    /// - Parameter target: target to be linted.
    /// - Returns: a linting issue if the target has more than one headers phase.
    fileprivate func lintOneHeadersPhase(target: Target) -> [LintingIssue] {
        let headerPhases = target.buildPhases
            .filter({ $0 is HeadersBuildPhase })
            .count
        if headerPhases <= 1 { return [] }
        return [LintingIssue(reason: "The target \(target.name) has more than one headers build phase.", severity: .error)]
    }
}
