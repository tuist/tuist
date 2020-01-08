import Basic
import Foundation

public struct ExecutionAction: Equatable {
    // MARK: - Attributes

    public let title: String
    public let scriptText: String
    public let target: TargetReference?

    // MARK: - Init

    public init(title: String,
                scriptText: String,
                target: TargetReference?) {
        self.title = title
        self.scriptText = scriptText
        self.target = target
    }
}
