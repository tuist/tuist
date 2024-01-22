import Foundation

/// An action that runs the built products.
public struct RunAction: Equatable, Codable {
    /// Indicates the build configuration the product should run with.
    public var configuration: ConfigurationName

    /// Whether a debugger should be attached to the run process or not.
    public var attachDebugger: Bool = true

    /// The path of custom lldbinit file.
    public var customLLDBInitFile: Path? = nil

    /// A list of actions that are executed before starting the run process.
    public var preActions: [ExecutionAction] = []

    /// A list of actions that are executed after the run process.
    public var postActions: [ExecutionAction] = []

    /// The name of the executable or target to run.
    public var executable: TargetReference? = nil

    /// Command line arguments passed on launch and environment variables.
    public var arguments: Arguments? = nil

    /// List of options to set to the action.
    public var options: RunActionOptions = .init()

    /// List of diagnostics options to set to the action.
    public var diagnosticsOptions: [SchemeDiagnosticsOption] = [.mainThreadChecker, .performanceAntipatternChecker],

    /// A target that will be used to expand the variables defined inside Environment Variables definition (e.g. $SOURCE_ROOT)
    public var expandVariableFromTarget: TargetReference? = nil

    /// The launch style of the action
    public var launchStyle: LaunchStyle = .automatically
}
