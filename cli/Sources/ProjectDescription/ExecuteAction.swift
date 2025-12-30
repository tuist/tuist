/// An action that can be executed as part of another action for pre or post execution.
public struct ExecutionAction: Equatable, Codable, Sendable {
    public var title: String
    public var scriptText: String
    public var target: TargetReference?

    /// The path to the shell which shall execute this script. if it is nil, Xcode will use default value.
    public var shellPath: String?

    public static func executionAction(
        title: String = "Run Script",
        scriptText: String,
        target: TargetReference? = nil,
        shellPath: String? = nil
    ) -> Self {
        self.init(
            title: title,
            scriptText: scriptText,
            target: target,
            shellPath: shellPath
        )
    }
}
