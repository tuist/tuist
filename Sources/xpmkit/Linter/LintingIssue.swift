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
        let issuesDescription = issues.map({ "- \($0.description)" }).joined(separator: "\n")
        return "The following errors have been found:\n\(issuesDescription)"
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
        return "\(severity.rawValue.uppercased()): \(reason)"
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
    func throwErrors() throws {
        let errorIssues = filter({ $0.severity == .error })
        if errorIssues.count == 0 { return }
        throw LintingError(issues: errorIssues)
    }
}
