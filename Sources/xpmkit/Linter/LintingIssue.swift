import Foundation

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
    private let reason: String

    /// Issue severity.
    private let severity: Severity

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

    var description: String {
        return "\(severity.rawValue.uppercased()): \(reason)"
    }

    // MARK: - Equatable

    static func == (lhs: LintingIssue, rhs: LintingIssue) -> Bool {
        return lhs.severity == rhs.severity &&
            lhs.reason == rhs.reason
    }
}

extension Array where Element == LintingIssue {
    func throwErrors() throws {
        // TODO:
    }
}
