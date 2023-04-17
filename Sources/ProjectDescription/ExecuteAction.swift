import Foundation

/// An action that can be executed as part of another action for pre or post execution.
public struct ExecutionAction: Equatable, Codable {
    public let title: String
    public let scriptText: String
    public let target: TargetReference?

    /// The path to the shell which shall execute this script. if it is nil, Xcode will use default value.
    public let shellPath: String?

    public init(title: String = "Run Script", scriptText: String, target: TargetReference? = nil, shellPath: String? = nil) {
        self.title = title
        self.scriptText = scriptText
        self.target = target
        self.shellPath = shellPath
    }
}
