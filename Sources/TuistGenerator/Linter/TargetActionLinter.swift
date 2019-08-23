import Foundation
import TuistCore

/// Protocol that defines the interface of a linter for target actions.
protocol TargetActionLinting {
    /// Lints a target aciton.
    ///
    /// - Parameter action: Action to be linted.
    /// - Returns: Found linting issues.
    func lint(_ action: TargetAction) -> [LintingIssue]
}

class TargetActionLinter: TargetActionLinting {
    // MARK: - Attributes

    /// System instance to run any commands in the system.
    private let system: Systeming

    // MARK: - Init

    /// Default initializer.
    ///
    /// - Parameter system: System instance to run any commands in the system.
    init(system: Systeming = System()) {
        self.system = system
    }

    func lint(_ action: TargetAction) -> [LintingIssue] {
        var issues: [LintingIssue] = []
        issues.append(contentsOf: lintToolExistence(action))
        issues.append(contentsOf: lintPathExistence(action))
        return issues
    }

    /// Lints a target aciton.
    ///
    /// - Parameter action: Action to be linted.
    /// - Returns: Found linting issues.
    func lintToolExistence(_ action: TargetAction) -> [LintingIssue] {
        guard let tool = action.tool else { return [] }
        do {
            _ = try system.which(tool)
            return []
        } catch {
            return [LintingIssue(reason: "The action tool '\(tool)' was not found in the environment",
                                 severity: .error)]
        }
    }

    func lintPathExistence(_ action: TargetAction) -> [LintingIssue] {
        guard let path = action.path else { return [] }
        if FileHandler.shared.exists(path) { return [] }
        return [LintingIssue(reason: "The action path \(path.pathString) doesn't exist",
                             severity: .error)]
    }
}
