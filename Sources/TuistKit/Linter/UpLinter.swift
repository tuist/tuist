import Foundation
import TuistCore
import TuistSupport

/// Protocol that defines an interface to lint Up tasks
protocol UpLinting {
    /// Lints an up task.
    ///
    /// - Parameter up: Task to be linted.
    /// - Returns: Array that contains all the linting issues.
    func lint(up: Upping) -> [LintingIssue]
}

final class UpLinter: UpLinting {
    /// Lints an up task.
    ///
    /// - Parameter up: Task to be linted.
    /// - Returns: Array that contains all the linting issues.
    func lint(up: Upping) -> [LintingIssue] {
        if let upCustom = up as? UpCustom {
            return lint(upCustom: upCustom)
        }
        return []
    }

    /// Lints a custom up task.
    ///
    /// - Parameter up: Task to be linted.
    /// - Returns: Array that contains all the linting issues.
    func lint(upCustom: UpCustom) -> [LintingIssue] {
        var issues: [LintingIssue] = []
        if upCustom.meet.isEmpty {
            let reason = "The up task '\(upCustom.name)' meet command is empty"
            issues.append(LintingIssue(reason: reason, severity: .error))
        }
        if upCustom.isMet.isEmpty {
            let reason = "The up task '\(upCustom.name)' isMet command is empty"
            issues.append(LintingIssue(reason: reason, severity: .error))
        }
        return issues
    }
}
