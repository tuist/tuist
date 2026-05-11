import Foundation
import Path

/// A execution action
public struct ExecutionAction: Equatable, Codable, Sendable {
    /// The source of build settings the action's script will receive via Xcode's
    /// `EnvironmentBuildable`. Choose `.target(...)` to bind to a specific target's
    /// build settings, or `.any` to let the scheme generator pick any of the scheme's
    /// surviving targets at generation time — useful when the script only depends on
    /// workspace-wide settings (`BUILD_DIR`, `CONFIGURATION`, `DERIVED_DATA_DIR`) and
    /// shouldn't pin a specific target through focus operations.
    public enum BuildSettingsSource: Equatable, Codable, Sendable {
        case target(TargetReference)
        case any
    }

    // MARK: - Attributes

    /// Name of a script.
    public let title: String
    /// An inline shell script.
    public let scriptText: String
    /// Source of the action's `EnvironmentBuildable` build settings.
    public let target: BuildSettingsSource?
    /// The path to the shell which shall execute this script. if it is nil, Xcode will use default value.
    public let shellPath: String?

    public let showEnvVarsInLog: Bool

    // MARK: - Init

    public init(
        title: String,
        scriptText: String,
        target: BuildSettingsSource?,
        shellPath: String?,
        showEnvVarsInLog: Bool = true
    ) {
        self.title = title
        self.scriptText = scriptText
        self.target = target
        self.shellPath = shellPath
        self.showEnvVarsInLog = showEnvVarsInLog
    }

    public init(
        title: String,
        scriptText: String,
        target: TargetReference,
        shellPath: String?,
        showEnvVarsInLog: Bool = true
    ) {
        self.init(
            title: title,
            scriptText: scriptText,
            target: .target(target),
            shellPath: shellPath,
            showEnvVarsInLog: showEnvVarsInLog
        )
    }
}
