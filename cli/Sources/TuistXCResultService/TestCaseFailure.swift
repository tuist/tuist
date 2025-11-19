import Foundation
import Path
import XCResultKit

public struct TestCaseFailure {
    public enum IssueType: String {
        case errorThrown = "Thrown Error"
        case assertionFailure = "Assertion Failure"
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

    init(_ actionTestFailureSummary: XCResultKit.ActionTestFailureSummary, rootDirectory: AbsolutePath?) {
        message = actionTestFailureSummary.message

        if let fileName = actionTestFailureSummary.fileName,
           let absolutePath = try? AbsolutePath(validating: fileName)
        {
            path = absolutePath.relative(to: rootDirectory ?? AbsolutePath.root)
        } else {
            path = nil
        }

        lineNumber = actionTestFailureSummary.lineNumber
        if let issueType = actionTestFailureSummary.issueType {
            self.issueType = IssueType(rawValue: issueType)
        } else {
            issueType = nil
        }
    }
}
