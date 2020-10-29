import Foundation
import TSCBasic
import TuistSupport

/// It represents a target build phase.
public struct TargetScript: Equatable {
    /// The  name of the build phase.
    public let name: String

    /// Script.
    public let script: String

    /// Whether we want the build phase to show the environment variables in the logs.
    public let showEnvVarsInLog: Bool

    /// Whether the script should be hashed for caching purposes.
    public let hashable: Bool

    /// Initializes the target script.
    /// - Parameter name: The name of the build phase.
    /// - Parameter script: Script.
    /// - Parameter showEnvVarsInLog: Whether we want the build phase to show the environment variables in the logs.
    /// - Parameter hashable: Whether the script should be hashed for caching purposes.
    public init(name: String,
                script: String,
                showEnvVarsInLog: Bool,
                hashable: Bool)
    {
        self.name = name
        self.script = script
        self.showEnvVarsInLog = showEnvVarsInLog
        self.hashable = hashable
    }
}
