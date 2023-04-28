import Foundation
import TSCBasic

/// A execution action
public struct ExecutionAction: Equatable, Codable {
    // MARK: - Attributes

    /// Name of a script.
    public let title: String
    /// An inline shell script.
    public let scriptText: String
    /// Name of the build or test target that will provide the action's build settings.
    public let target: TargetReference?
    /// The path to the shell which shall execute this script. if it is nil, Xcode will use default value.
    public let shellPath: String?

    public let showEnvVarsInLog: Bool

    // MARK: - Init

    public init(
        title: String,
        scriptText: String,
        target: TargetReference?,
        shellPath: String?,
        showEnvVarsInLog: Bool = true
    ) {
        self.title = title
        self.scriptText = scriptText
        self.target = target
        self.shellPath = shellPath
        self.showEnvVarsInLog = showEnvVarsInLog
    }
}
