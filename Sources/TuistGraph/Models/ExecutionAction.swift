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

    public let showEnvVarsInLog: Bool

    // MARK: - Init

    public init(
        title: String,
        scriptText: String,
        target: TargetReference?,
        showEnvVarsInLog: Bool = true
    ) {
        self.title = title
        self.scriptText = scriptText
        self.target = target
        self.showEnvVarsInLog = showEnvVarsInLog
    }
}
