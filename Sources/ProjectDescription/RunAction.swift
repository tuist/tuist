import Foundation

/// It represents the test action of a scheme.
public struct RunAction: Equatable, Codable {
    /// Name of the configuration that should be used for building the runnable targets.
    public let configurationName: String

    /// Executable that will be run.
    public let executable: TargetReference?

    /// Arguments passed to the process running the app.
    public let arguments: Arguments?

    /// Run action options
    public let options: RunActionOptions

    /// Diagnostics options.
    public let diagnosticsOptions: [SchemeDiagnosticsOption]

    /// Initializes a new instance of a run action.
    /// - Parameters:
    ///   - configurationName: Name of the configuration that should be used for building the runnable targets.
    ///   - executable: Executable that will be run.
    ///   - arguments: Arguments passed to the process running the app.
    ///   - options: Run action options.
    ///   - diagnosticsOptions: Diagnostics options.
    public init(configurationName: String,
                executable: TargetReference? = nil,
                arguments: Arguments? = nil,
                options: RunActionOptions = .options(),
                diagnosticsOptions: [SchemeDiagnosticsOption] = [])
    {
        self.configurationName = configurationName
        self.executable = executable
        self.arguments = arguments
        self.options = options
        self.diagnosticsOptions = diagnosticsOptions
    }

    /// Initializes a new instance of a run action.
    /// - Parameters:
    ///   - config: Configuration that should be used for building the test targets.
    ///   - executable: Executable that will be run.
    ///   - arguments: Arguments passed to the process running the app.
    ///   - options: Run action options.
    ///   - diagnosticsOptions: Diagnostics options.
    public init(config: PresetBuildConfiguration = .debug,
                executable: TargetReference? = nil,
                arguments: Arguments? = nil,
                options: RunActionOptions = .options(),
                diagnosticsOptions: [SchemeDiagnosticsOption] = [])
    {
        self.init(configurationName: config.name,
                  executable: executable,
                  arguments: arguments,
                  options: options,
                  diagnosticsOptions: diagnosticsOptions)
    }
}
