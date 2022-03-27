import Foundation

/// An action that profiles the built products.
///
/// It's initialized with the `.profileAction` static method
public struct ProfileAction: Equatable, Codable {
    /// Indicates the build configuration the product should be profiled with.
    public let configuration: ConfigurationName

    /// A list of actions that are executed before starting the profile process.
    public let preActions: [ExecutionAction]

    /// A list of actions that are executed after the profile process.
    public let postActions: [ExecutionAction]

    /// The name of the executable or target to profile.
    public let executable: TargetReference?

    /// Command line arguments passed on launch and environment variables.
    public let arguments: Arguments?

    init(
        configuration: ConfigurationName = .release,
        preActions: [ExecutionAction] = [],
        postActions: [ExecutionAction] = [],
        executable: TargetReference? = nil,
        arguments: Arguments? = nil
    ) {
        self.configuration = configuration
        self.preActions = preActions
        self.postActions = postActions
        self.executable = executable
        self.arguments = arguments
    }

    /// Returns a profile action.
    /// - Parameters:
    ///   - configuration: Indicates the build configuration the product should be profiled with.
    ///   - preActions: A list of actions that are executed before starting the profile process.
    ///   - postActions: A list of actions that are executed after the profile process.
    ///   - executable: The name of the executable or target to profile.
    ///   - arguments: Command line arguments passed on launch and environment variables.
    /// - Returns: Initialized profile action.
    public static func profileAction(
        configuration: ConfigurationName = .release,
        preActions: [ExecutionAction] = [],
        postActions: [ExecutionAction] = [],
        executable: TargetReference? = nil,
        arguments: Arguments? = nil
    ) -> ProfileAction {
        ProfileAction(
            configuration: configuration,
            preActions: preActions,
            postActions: postActions,
            executable: executable,
            arguments: arguments
        )
    }
}
