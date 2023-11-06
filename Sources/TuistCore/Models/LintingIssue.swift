import Foundation
import TuistSupport

public struct LintingError: FatalError, Equatable {
    public let description: String = "Fatal linting issues found"
    public let type: ErrorType = .abort
    public init() {}
}

/// Linting issue.
public struct LintingIssue: CustomStringConvertible, Equatable {
    public enum Severity: String {
        case warning
        case error
    }

    // MARK: - Attributes

    public let reason: String
    public let severity: Severity

    // MARK: - Init

    public init(reason: String, severity: Severity) {
        self.reason = reason
        self.severity = severity
    }

    // MARK: - CustomStringConvertible

    public var description: String {
        reason
    }
}

// MARK: - Array Extension (Linting issues)

extension [LintingIssue] {
    public func printAndThrowErrorsIfNeeded() throws {
        if count == 0 { return }

        let errorIssues = filter { $0.severity == .error }

        for issue in errorIssues {
            logger.error("\(issue.description)")
        }

        if !errorIssues.isEmpty { throw LintingError() }
    }

    public func printWarningsIfNeeded() {
        if count == 0 { return }
        let warningIssues = filter { $0.severity == .warning }
        for issue in warningIssues {
            WarningController.shared.append(warning: issue.description)
        }
    }
}
