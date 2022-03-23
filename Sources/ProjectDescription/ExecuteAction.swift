import Foundation

/// An action that can be executed as part of another action for pre or post execution.
public struct ExecutionAction: Equatable, Codable {
    public let title: String
    public let scriptText: String
    public let target: TargetReference?

    public init(title: String = "Run Script", scriptText: String, target: TargetReference? = nil) {
        self.title = title
        self.scriptText = scriptText
        self.target = target
    }
}
