import Foundation
import TuistCore

struct LintingError: FatalError, Equatable {

    // MARK: - Attributes

    private let issues: [LintingIssue]

    // MARK: - Init

    init(issues: [LintingIssue]) {
        self.issues = issues
    }

    // MARK: - FatalError

    var description: String {
        return issues.map({ "- \($0.description)" }).joined(separator: "\n")
    }

    var type: ErrorType {
        return .abort
    }

    static func == (lhs: LintingError, rhs: LintingError) -> Bool {
        return lhs.issues == rhs.issues
    }
}

/// Linting issue.
struct LintingIssue: CustomStringConvertible, Equatable {
    enum Severity: String {
        case warning
        case error
    }

    // MARK: - Attributes

    let reason: String
    let severity: Severity

    // MARK: - Init

    init(reason: String, severity: Severity) {
        self.reason = reason
        self.severity = severity
    }

    // MARK: - CustomStringConvertible

    var description: String {
        return reason
    }

    // MARK: - Equatable

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
