import Foundation
import Path

public struct TestCaseFailure: Encodable, Sendable {
    public enum IssueType: String, Encodable, Sendable {
        case errorThrown = "Thrown Error"
        case assertionFailure = "Assertion Failure"
        case issueRecorded = "Issue Recorded"
    }

    public let message: String?
    public let path: RelativePath?
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
        path: RelativePath?,
        lineNumber: Int,
        issueType: IssueType?
    ) {
        self.message = message
        self.path = path
        self.lineNumber = lineNumber
        self.issueType = issueType
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(message, forKey: .message)
        try container.encodeIfPresent(path?.pathString, forKey: .path)
        try container.encode(lineNumber, forKey: .lineNumber)
        try container.encodeIfPresent(issueType, forKey: .issueType)
    }
}
