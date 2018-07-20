import Foundation
import xpmcore

/// Linting errors.
struct LintingError: FatalError, Equatable {

    // MARK: - Attributes

    /// Linting issues.
    private let issues: [LintingIssue]

    /// Initializes the error with the linting issues.
    ///
    /// - Parameter issues: issues.
    init(issues: [LintingIssue]) {
        self.issues = issues
    }

    /// Error description.
    var description: String {
        return issues.map({ "- \($0.description)" }).joined(separator: "\n")
    }

    /// Error type.
    var type: ErrorType {
        return .abort
    }

    /// Compares two instances of LintingError.
    ///
    /// - Parameters:
    ///   - lhs: first instance to be compared.
    ///   - rhs: second instance to be compared.
    /// - Returns: true if the two instances are the same.
    static func == (lhs: LintingError, rhs: LintingError) -> Bool {
        return lhs.issues == rhs.issues
    }
}

/// Linting issue.
struct LintingIssue: CustomStringConvertible, Equatable {
    /// Issue severities.
    ///
    /// - warning: used for issues that the developer should be alerted about but that shouldn't error the process.
    /// - error: used for issues that should error the process.
    enum Severity: String {
        case warning
        case error
    }

    // MARK: - Attributes

    /// Issue reason.
    fileprivate let reason: String

    /// Issue severity.
    fileprivate let severity: Severity

    /// Default LintingIssue constructor.
    ///
    /// - Parameters:
    ///   - reason: issue reason.
    ///   - severity: issue severity
    init(reason: String, severity: Severity) {
        self.reason = reason
        self.severity = severity
    }

    // MARK: - CustomStringConvertible

    /// Description.
    var description: String {
        return reason
    }

    // MARK: - Equatable

    /// Compares two instances of LintingIssue.
    ///
    /// - Parameters:
    ///   - lhs: first instance to be compared.
    ///   - rhs: second instance to be compared.
    /// - Returns: true if the two instances are equal.
    static func == (lhs: LintingIssue, rhs: LintingIssue) -> Bool {
        return lhs.severity == rhs.severity &&
            lhs.reason == rhs.reason
    }
}

// MARK: - Array Extension (Linting issues)

extension Array where Element == LintingIssue {
    func printAndThrowIfNeeded(printer: Printing) throws {
        if count == 0 { return }

        let errorIssues = filter({ $0.severity == .error })
        let warningIssues = filter({ $0.severity == .warning })

        if warningIssues.count != 0 {
            let message = "The following issues have been found:\n"
            let warningsMessage = message.appending(warningIssues
                .map({ "- \($0.description)" })
                .joined(separator: "\n"))
            printer.print(warning: warningsMessage)
        }

        if errorIssues.count != 0 {
            let message = "The following critical issues have been found:\n"
            let errorMessage = message.appending(errorIssues
                .map({ "- \($0.description)" })
                .joined(separator: "\n"))
            printer.print(errorMessage: errorMessage)

            throw LintingError(issues: errorIssues)
        }
    }
}
