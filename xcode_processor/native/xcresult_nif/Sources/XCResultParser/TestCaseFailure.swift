import Foundation

public struct TestCaseFailure: Encodable, Sendable {
    public enum IssueType: String, Encodable, Sendable {
        case errorThrown = "Thrown Error"
        case assertionFailure = "Assertion Failure"
        case issueRecorded = "Issue Recorded"
    }

    public let message: String?
    public let path: String?
    public let lineNumber: Int
    public let issueType: IssueType?

    enum CodingKeys: String, CodingKey {
        case message
        case path
        case lineNumber = "line_number"
        case issueType = "issue_type"
    }

    public init(
        message: String?,
        path: String?,
        lineNumber: Int,
        issueType: IssueType?
    ) {
        self.message = message
        self.path = path
        self.lineNumber = lineNumber
        self.issueType = issueType
    }
}
