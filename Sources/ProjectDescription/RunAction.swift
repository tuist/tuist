import Foundation

/// It represents the test action of a scheme.
public struct RunAction: Equatable, Codable {
    /// Name of the configuration that should be used for building the runnable targets.
    public let configuration: ConfigurationName

    /// List of actions to be executed before running.
    public let preActions: [ExecutionAction]

    /// List of actions to be executed after running.
    public let postActions: [ExecutionAction]

    /// Executable that will be run.
    public let executable: TargetReference?

    /// Arguments passed to the process running the app.
    public let arguments: Arguments?

    /// Run action options
    public let options: RunActionOptions

    /// Diagnostics options.
    public let diagnosticsOptions: [SchemeDiagnosticsOption]

    init(configuration: ConfigurationName,
         preActions: [ExecutionAction] = [],
         postActions: [ExecutionAction] = [],
         executable: TargetReference? = nil,
         arguments: Arguments? = nil,
         options: RunActionOptions = .options(),
         diagnosticsOptions: [SchemeDiagnosticsOption] = [.mainThreadChecker])
    {
        self.configuration = configuration
        self.preActions = preActions
        self.postActions = postActions
        self.executable = executable
        self.arguments = arguments
        self.options = options
        self.diagnosticsOptions = diagnosticsOptions
    }

    /// Initializes a new instance of a run action.
    /// - Parameters:
    ///   - configuration: Name of the configuration that should be used for building the runnable targets.
    ///   - preActions: Actions to execute before running.
    ///   - postActions: Actions to execute after running.
    ///   - executable: Executable that will be run.
    ///   - arguments: Arguments passed to the process running the app.
    ///   - options: Run action options.
    ///   - diagnosticsOptions: Diagnostics options.
    /// - Returns: Run action.
    public static func runAction(configuration: ConfigurationName = .debug,
                                 preActions: [ExecutionAction] = [],
                                 postActions: [ExecutionAction] = [],
                                 executable: TargetReference? = nil,
                                 arguments: Arguments? = nil,
                                 options: RunActionOptions = .options(),
                                 diagnosticsOptions: [SchemeDiagnosticsOption] = [.mainThreadChecker]) -> RunAction
    {
        return RunAction(
            configuration: configuration,
            preActions: preActions,
            postActions: postActions,
            executable: executable,
            arguments: arguments,
            options: options,
            diagnosticsOptions: diagnosticsOptions
        )
    }
}
