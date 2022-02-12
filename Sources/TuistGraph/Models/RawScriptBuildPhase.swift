import Foundation
import TSCBasic

/// It represents a raw script build phase.
public struct RawScriptBuildPhase: Equatable, Codable {
    /// The  name of the build phase.
    public let name: String

    /// Script.
    public let script: String

    /// Whether we want the build phase to show the environment variables in the logs.
    public let showEnvVarsInLog: Bool

    /// Whether the script should be hashed for caching purposes.
    public let hashable: Bool

    /// The path to the shell which shall execute this script.
    public let shellPath: String

    /// Initializes the target script.
    /// - Parameter name: The name of the build phase.
    /// - Parameter script: Script.
    /// - Parameter showEnvVarsInLog: Whether we want the build phase to show the environment variables in the logs.
    /// - Parameter hashable: Whether the script should be hashed for caching purposes.
    /// - Parameter shellPath: The path to the shell which shall execute this script. Default is `/bin/sh`.
    public init(
        name: String,
        script: String,
        showEnvVarsInLog: Bool,
        hashable: Bool,
        shellPath: String = "/bin/sh"
    ) {
        self.name = name
        self.script = script
        self.showEnvVarsInLog = showEnvVarsInLog
        self.hashable = hashable
        self.shellPath = shellPath
    }
}
