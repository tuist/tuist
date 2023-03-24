import Foundation

/// An action that runs the built products.
///
/// It's initialized with the .runAction static method.
public struct RunAction: Equatable, Codable {
    /// Indicates the build configuration the product should run with.
    public let configuration: ConfigurationName

    /// Whether a debugger should be attached to the run process or not.
    public let attachDebugger: Bool

    /// The path of custom lldbinit file.
    public let customLLDBInitFile: Path?

    /// A list of actions that are executed before starting the run process.
    public let preActions: [ExecutionAction]

    /// A list of actions that are executed after the run process.
    public let postActions: [ExecutionAction]

    /// The name of the executable or target to run.
    public let executable: TargetReference?

    /// Command line arguments passed on launch and environment variables.
    public let arguments: Arguments?

    /// List of options to set to the action.
    public let options: RunActionOptions

    /// List of diagnostics options to set to the action.
    public let diagnosticsOptions: [SchemeDiagnosticsOption]

    init(
        configuration: ConfigurationName,
        attachDebugger: Bool = true,
        customLLDBInitFile: Path? = nil,
        preActions: [ExecutionAction] = [],
        postActions: [ExecutionAction] = [],
        executable: TargetReference? = nil,
        arguments: Arguments? = nil,
        options: RunActionOptions = .options(),
        diagnosticsOptions: [SchemeDiagnosticsOption] = [.mainThreadChecker, .performanceAntipatternChecker]
    ) {
        self.configuration = configuration
        self.attachDebugger = attachDebugger
        self.customLLDBInitFile = customLLDBInitFile
        self.preActions = preActions
        self.postActions = postActions
        self.executable = executable
        self.arguments = arguments
        self.options = options
        self.diagnosticsOptions = diagnosticsOptions
    }

    /// Returns a run action.
    /// - Parameters:
    ///   - configuration: Indicates the build configuration the product should run with.
    ///   - attachDebugger: Whether a debugger should be attached to the run process or not.
    ///   - preActions: A list of actions that are executed before starting the run process.
    ///   - postActions: A list of actions that are executed after the run process.
    ///   - executable: The name of the executable or target to run.
    ///   - arguments: Command line arguments passed on launch and environment variables.
    ///   - options: List of options to set to the action.
    ///   - diagnosticsOptions: List of diagnostics options to set to the action.
    /// - Returns: Run action.
    public static func runAction(
        configuration: ConfigurationName = .debug,
        attachDebugger: Bool = true,
        customLLDBInitFile: Path? = nil,
        preActions: [ExecutionAction] = [],
        postActions: [ExecutionAction] = [],
        executable: TargetReference? = nil,
        arguments: Arguments? = nil,
        options: RunActionOptions = .options(),
        diagnosticsOptions: [SchemeDiagnosticsOption] = [.mainThreadChecker]
    ) -> RunAction {
        RunAction(
            configuration: configuration,
            attachDebugger: attachDebugger,
            customLLDBInitFile: customLLDBInitFile,
            preActions: preActions,
            postActions: postActions,
            executable: executable,
            arguments: arguments,
            options: options,
            diagnosticsOptions: diagnosticsOptions
        )
    }
}
