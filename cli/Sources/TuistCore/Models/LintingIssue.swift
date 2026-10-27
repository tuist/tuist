import Foundation
import TuistAlert
import TuistConfig
import TuistLogging
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
    public let category: TuistGeneratedProjectOptions.GenerationOptions.GenerationWarning?

    // MARK: - Init

    public init(
        reason: String,
        severity: Severity,
        category: TuistGeneratedProjectOptions.GenerationOptions.GenerationWarning? = nil
    ) {
        self.reason = reason
        self.severity = severity
        self.category = category
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
            Logger.current.error("\(issue.description)")
        }

        if !errorIssues.isEmpty { throw LintingError() }
    }

    public func printWarningsIfNeeded() {
        if count == 0 { return }

        let warningIssues = filter { $0.severity == .warning }
        for issue in warningIssues {
            AlertController.current.warning(.alert("\(issue.description)"))
        }
    }

    public func promotingWarnings(
        with warningsAsErrors: TuistGeneratedProjectOptions.GenerationOptions.WarningsAsErrors
    ) -> [LintingIssue] {
        map { issue in
            guard issue.severity == .warning else { return issue }
            let shouldPromote: Bool
            switch warningsAsErrors {
            case .none:
                shouldPromote = false
            case .all:
                shouldPromote = true
            case let .only(categories):
                if let category = issue.category {
                    shouldPromote = categories.contains(category)
                } else {
                    shouldPromote = false
                }
            }
            if shouldPromote {
                return LintingIssue(reason: issue.reason, severity: .error, category: issue.category)
            }
            return issue
        }
    }
}
