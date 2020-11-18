import Foundation
import TSCBasic

public struct ExecutionAction: Equatable {
    // MARK: - Attributes

    public let title: String
    public let scriptText: String
    public let target: TargetReference?
    public let showEnvVarsInLog: Bool

    // MARK: - Init

    public init(title: String,
                scriptText: String,
                target: TargetReference?,
                showEnvVarsInLog: Bool = true)
    {
        self.title = title
        self.scriptText = scriptText
        self.target = target
        self.showEnvVarsInLog = showEnvVarsInLog
    }
}
