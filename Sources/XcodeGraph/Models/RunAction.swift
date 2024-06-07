import Foundation
import Path

public struct RunAction: Equatable, Codable {
    // MARK: - Attributes

    public let configurationName: String
    public let attachDebugger: Bool
    public let customLLDBInitFile: AbsolutePath?
    public let preActions: [ExecutionAction]
    public let postActions: [ExecutionAction]
    public let executable: TargetReference?
    public let filePath: AbsolutePath?
    public let arguments: Arguments?
    public let options: RunActionOptions
    public let diagnosticsOptions: SchemeDiagnosticsOptions
    public let expandVariableFromTarget: TargetReference?
    public let launchStyle: LaunchStyle

    // MARK: - Init

    public init(
        configurationName: String,
        attachDebugger: Bool,
        customLLDBInitFile: AbsolutePath?,
        preActions: [ExecutionAction] = [],
        postActions: [ExecutionAction] = [],
        executable: TargetReference?,
        filePath: AbsolutePath?,
        arguments: Arguments?,
        options: RunActionOptions = .init(),
        diagnosticsOptions: SchemeDiagnosticsOptions,
        expandVariableFromTarget: TargetReference? = nil,
        launchStyle: LaunchStyle = .automatically
    ) {
        self.configurationName = configurationName
        self.attachDebugger = attachDebugger
        self.customLLDBInitFile = customLLDBInitFile
        self.preActions = preActions
        self.postActions = postActions
        self.executable = executable
        self.filePath = filePath
        self.arguments = arguments
        self.options = options
        self.diagnosticsOptions = diagnosticsOptions
        self.expandVariableFromTarget = expandVariableFromTarget
        self.launchStyle = launchStyle
    }
}
