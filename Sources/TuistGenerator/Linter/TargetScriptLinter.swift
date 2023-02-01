import Foundation
import TuistCore
import TuistGraph
import TuistSupport

/// Protocol that defines the interface of a linter for target scripts.
protocol TargetScriptLinting {
    /// Lints a target action.
    ///
    /// - Parameter action: Action to be linted.
    /// - Returns: Found linting issues.
    func lint(_ script: TargetScript) -> [LintingIssue]
}

class TargetScriptLinter: TargetScriptLinting {
    func lint(_ script: TargetScript) -> [LintingIssue] {
        var issues: [LintingIssue] = []
        issues.append(contentsOf: lintEmbeddedScriptNotEmpty(script))
        issues.append(contentsOf: lintToolExistence(script))
        issues.append(contentsOf: lintPathExistence(script))
        return issues
    }

    private func lintEmbeddedScriptNotEmpty(_ script: TargetScript) -> [LintingIssue] {
        guard let script = script.embeddedScript,
              script.isEmpty
        else { return [] }

        return [
            LintingIssue(reason: "The embedded script is empty", severity: .warning),
        ]
    }

    /// Lints a target action.
    ///
    /// - Parameter action: Action to be linted.
    /// - Returns: Found linting issues.
    private func lintToolExistence(_ script: TargetScript) -> [LintingIssue] {
        guard let tool = script.tool
        else { return [] }
        do {
            _ = try System.shared.which(tool)
            return []
        } catch {
            return [LintingIssue(
                reason: "The script tool '\(tool)' was not found in the environment",
                severity: .error
            )]
        }
    }

    private func lintPathExistence(_ script: TargetScript) -> [LintingIssue] {
        guard let path = script.path,
              !FileHandler.shared.exists(path)
        else { return [] }
        return [LintingIssue(
            reason: "The script path \(path.pathString) doesn't exist",
            severity: .error
        )]
    }
}
