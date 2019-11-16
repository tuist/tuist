import Foundation
import TuistSupport

public struct LintingError: FatalError, Equatable {
    public var description: String = "Fatal linting issues found"
    public var type: ErrorType = .abort
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
        return reason
    }

    // MARK: - Equatable

    public static func == (lhs: LintingIssue, rhs: LintingIssue) -> Bool {
        return lhs.severity == rhs.severity &&
            lhs.reason == rhs.reason
    }
}

// MARK: - Array Extension (Linting issues)

public extension Array where Element == LintingIssue {
    func printAndThrowIfNeeded() throws {
        if count == 0 { return }

        let errorIssues = filter { $0.severity == .error }
        let warningIssues = filter { $0.severity == .warning }

        if !warningIssues.isEmpty {
            let message = warningIssues.map { "- \($0.description)" }.joined(separator: "\n")
            Printer.shared.print(warning: message)
        }

        if !errorIssues.isEmpty {
            let message = errorIssues.map { "- \($0.description)" }.joined(separator: "\n")
            Printer.shared.print(errorMessage: message)

            throw LintingError()
        }
    }
}
