import Foundation

/// It represents the test action of a scheme.
public struct RunAction: Equatable, Codable {
    /// Name of the configuration that should be used for building the runnable targets.
    public let configuration: ConfigurationName

    /// Executable that will be run.
    public let executable: TargetReference?

    /// Arguments passed to the process running the app.
    public let arguments: Arguments?

    /// Run action options
    public let options: RunActionOptions

    /// Diagnostics options.
    public let diagnosticsOptions: [SchemeDiagnosticsOption]

    init(configuration: ConfigurationName,
         executable: TargetReference? = nil,
         arguments: Arguments? = nil,
         options: RunActionOptions = .options(),
         diagnosticsOptions: [SchemeDiagnosticsOption] = [.mainThreadChecker])
    {
        self.configuration = configuration
        self.executable = executable
        self.arguments = arguments
        self.options = options
        self.diagnosticsOptions = diagnosticsOptions
    }

    /// Initializes a new instance of a run action.
    /// - Parameters:
    ///   - configuration: Name of the configuration that should be used for building the runnable targets.
    ///   - executable: Executable that will be run.
    ///   - arguments: Arguments passed to the process running the app.
    ///   - options: Run action options.
    ///   - diagnosticsOptions: Diagnostics options.
    /// - Returns: Run action.
    public static func runAction(configuration: ConfigurationName,
                                 executable: TargetReference? = nil,
                                 arguments: Arguments? = nil,
                                 options: RunActionOptions = .options(),
                                 diagnosticsOptions: [SchemeDiagnosticsOption] = [.mainThreadChecker]) -> RunAction
    {
        return RunAction(
            configuration: configuration,
            executable: executable,
            arguments: arguments,
            options: options,
            diagnosticsOptions: diagnosticsOptions
        )
    }
}
