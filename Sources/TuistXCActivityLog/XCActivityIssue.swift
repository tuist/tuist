import Foundation
import Path

public struct XCActivityIssue {
    public let type: XCActivityIssueType
    public let target: String
    public let project: String
    public let title: String
    public let signature: String
    public let stepType: XCActivityStepType
    public let path: RelativePath?
    public let message: String?
    public let startingLine: Int
    public let endingLine: Int
    public let startingColumn: Int
    public let endingColumn: Int
}

public enum XCActivityIssueType {
    case warning, error
}
