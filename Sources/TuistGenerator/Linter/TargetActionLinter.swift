import Foundation
import TuistCore
import TuistSupport

/// Protocol that defines the interface of a linter for target actions.
protocol TargetActionLinting {
    /// Lints a target aciton.
    ///
    /// - Parameter action: Action to be linted.
    /// - Returns: Found linting issues.
    func lint(_ action: TargetAction) -> [LintingIssue]
}

class TargetActionLinter: TargetActionLinting {
    func lint(_ action: TargetAction) -> [LintingIssue] {
        var issues: [LintingIssue] = []
        issues.append(contentsOf: lintEmbeddedScriptNotEmpty(action))
        issues.append(contentsOf: lintToolExistence(action))
        issues.append(contentsOf: lintPathExistence(action))
        return issues
    }

    private func lintEmbeddedScriptNotEmpty(_ action: TargetAction) -> [LintingIssue] {
        guard let script = action.embeddedScript,
              script.isEmpty
        else { return [] }

        return [
            LintingIssue(reason: "The embedded script is empty", severity: .warning)
        ]
    }
    
    /// Lints a target aciton.
    ///
    /// - Parameter action: Action to be linted.
    /// - Returns: Found linting issues.
    private func lintToolExistence(_ action: TargetAction) -> [LintingIssue] {
        guard
            let tool = action.tool
        else { return [] }
        do {
            _ = try System.shared.which(tool)
            return []
        } catch {
            return [LintingIssue(reason: "The action tool '\(tool)' was not found in the environment",
                                 severity: .error)]
        }
    }

    private func lintPathExistence(_ action: TargetAction) -> [LintingIssue] {
        guard
            let path = action.path,
            !FileHandler.shared.exists(path)
        else { return [] }
        return [LintingIssue(reason: "The action path \(path.pathString) doesn't exist",
                             severity: .error)]
    }
}
