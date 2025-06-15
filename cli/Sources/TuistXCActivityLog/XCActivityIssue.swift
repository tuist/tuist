import Foundation
import Path

public struct XCActivityIssue: Hashable, Equatable {
    public let type: XCActivityIssueType
    public let target: String
    public let project: String
    public let title: String
    public let signature: String
    public let stepType: XCActivityStepType
    public let path: RelativePath?
    public var message: String?
    public let startingLine: Int
    public let endingLine: Int
    public let startingColumn: Int
    public let endingColumn: Int
}

public enum XCActivityIssueType: Hashable, Equatable {
    case warning, error
}

#if DEBUG
    extension XCActivityIssue {
        public static func test(
            type: XCActivityIssueType = .warning,
            target: String = "Target",
            project: String = "Project",
            title: String = "Title",
            signature: String = "Signature",
            stepType: XCActivityStepType = .swiftCompilation,
            path: RelativePath? = nil,
            message: String? = nil,
            startingLine: Int = 1,
            endingLine: Int = 1,
            startingColumn: Int = 1,
            endingColumn: Int = 1
        ) -> XCActivityIssue {
            self.init(
                type: type,
                target: target,
                project: project,
                title: title,
                signature: signature,
                stepType: stepType,
                path: path,
                message: message,
                startingLine: startingLine,
                endingLine: endingLine,
                startingColumn: startingColumn,
                endingColumn: endingColumn
            )
        }
    }
#endif
