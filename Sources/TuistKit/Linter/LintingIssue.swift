import Foundation
import TuistCore

struct LintingError: FatalError, Equatable {
    var description: String = "Fatal linting issues found"
    var type: ErrorType = .abort
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

        if !warningIssues.isEmpty {
            printer.print("The following issues have been found:", color: .yellow)
            let message = warningIssues.map({ "  - \($0.description)" }).joined(separator: "\n")
            printer.print(message)
        }

        if !errorIssues.isEmpty {
            let prefix = !warningIssues.isEmpty ? "\n" : ""
            printer.print("\(prefix)The following critical issues have been found:", color: .red)
            let message = errorIssues.map({ "  - \($0.description)" }).joined(separator: "\n")
            printer.print(message)

            throw LintingError()
        }
    }
}
