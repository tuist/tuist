import Foundation

public struct ProfileAction: Equatable, Codable {
    /// Name of the configuration that should be used for the Analyze action
    public let configuration: ConfigurationName

    /// List of actions to be executed before running the Analyze action
    public let preActions: [ExecutionAction]

    /// List of actions to be executed after running the Analyze action
    public let postActions: [ExecutionAction]

    /// The executable to profile
    public let executable: TargetReference?

    /// Arguments to pass when launching the executable
    public let arguments: Arguments?

    init(configuration: ConfigurationName = .release,
         preActions: [ExecutionAction] = [],
         postActions: [ExecutionAction] = [],
         executable: TargetReference? = nil,
         arguments: Arguments? = nil)
    {
        self.configuration = configuration
        self.preActions = preActions
        self.postActions = postActions
        self.executable = executable
        self.arguments = arguments
    }

    /// Initializes a profile action.
    /// - Parameters:
    ///   - configuration: Configuration to be used for profiling.
    ///   - preActions: Actions to be run before the Profile action
    ///   - postActions: Actions to be run after the Profile action
    ///   - executable: Profiled executable.
    ///   - arguments: Arguments to pass when launching the executable.
    /// - Returns: Initialized profile action.
    public static func profileAction(configuration: ConfigurationName = .release,
                                     preActions: [ExecutionAction] = [],
                                     postActions: [ExecutionAction] = [],
                                     executable: TargetReference? = nil,
                                     arguments: Arguments? = nil) -> ProfileAction
    {
        return ProfileAction(
            configuration: configuration,
            preActions: preActions,
            postActions: postActions,
            executable: executable,
            arguments: arguments
        )
    }
}
