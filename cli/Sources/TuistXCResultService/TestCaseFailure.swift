import Foundation
import Path

public struct TestCaseFailure {
    public enum IssueType: String {
        case errorThrown = "Thrown Error"
        case assertionFailure = "Assertion Failure"
        case issueRecorded = "Issue Recorded"
    }

    public let message: String?
    public let path: RelativePath?
    public let lineNumber: Int
    public let issueType: IssueType?

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
}
