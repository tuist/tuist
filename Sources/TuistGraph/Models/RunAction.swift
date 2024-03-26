import Foundation
import TSCBasic

public struct RunAction: Equatable, Codable {
    // MARK: - Attributes

    public var configurationName: String
    public var attachDebugger: Bool
    public var customLLDBInitFile: AbsolutePath?
    public var preActions: [ExecutionAction]
    public var postActions: [ExecutionAction]
    public var executable: TargetReference?
    public var filePath: AbsolutePath?
    public var arguments: Arguments?
    public var options: RunActionOptions
    public var diagnosticsOptions: SchemeDiagnosticsOptions
    public var expandVariableFromTarget: TargetReference?
    public var launchStyle: LaunchStyle

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
