import Foundation

/// An action that can be executed as part of another action for pre or post execution.
public struct ExecutionAction: Equatable, Codable {
    public var title: String
    public var scriptText: String
    public var target: TargetReference?

    /// The path to the shell which shall execute this script. if it is nil, Xcode will use default value.
    public var shellPath: String?

    public init(title: String = "Run Script", scriptText: String, target: TargetReference? = nil, shellPath: String? = nil) {
        self.title = title
        self.scriptText = scriptText
        self.target = target
        self.shellPath = shellPath
    }
}
