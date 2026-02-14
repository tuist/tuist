/// An action that profiles the built products.
///
/// It's initialized with the `.profileAction` static method
public struct ProfileAction: Equatable, Codable, Sendable {
    /// Indicates the build configuration the product should be profiled with.
    public var configuration: ConfigurationName

    /// A list of actions that are executed before starting the profile process.
    public var preActions: [ExecutionAction]

    /// A list of actions that are executed after the profile process.
    public var postActions: [ExecutionAction]

    /// The name of the executable or target to profile.
    public var executable: TargetReference?

    /// Whether to present the "Ask on Launch" dialog when profiling.
    public var askForAppToLaunch: Bool

    /// Command line arguments passed on launch and environment variables.
    public var arguments: Arguments?

    init(
        configuration: ConfigurationName = .release,
        preActions: [ExecutionAction] = [],
        postActions: [ExecutionAction] = [],
        executable: TargetReference? = nil,
        askForAppToLaunch: Bool = false,
        arguments: Arguments? = nil
    ) {
        self.configuration = configuration
        self.preActions = preActions
        self.postActions = postActions
        self.executable = executable
        self.askForAppToLaunch = askForAppToLaunch
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

    /// Returns a profile action with an executable configuration.
    /// - Parameters:
    ///   - configuration: Indicates the build configuration the product should be profiled with.
    ///   - preActions: A list of actions that are executed before starting the profile process.
    ///   - postActions: A list of actions that are executed after the profile process.
    ///   - executable: The executable configuration, either `.askOnLaunch` or `.executable(TargetReference?)`.
    ///   - arguments: Command line arguments passed on launch and environment variables.
    /// - Returns: Initialized profile action.
    public static func profileAction(
        configuration: ConfigurationName = .release,
        preActions: [ExecutionAction] = [],
        postActions: [ExecutionAction] = [],
        executable: Executable,
        arguments: Arguments? = nil
    ) -> ProfileAction {
        let askForAppToLaunch: Bool
        let targetReference: TargetReference?
        switch executable {
        case .askOnLaunch:
            askForAppToLaunch = true
            targetReference = nil
        case let .executable(reference):
            askForAppToLaunch = false
            targetReference = reference
        }
        return ProfileAction(
            configuration: configuration,
            preActions: preActions,
            postActions: postActions,
            executable: targetReference,
            askForAppToLaunch: askForAppToLaunch,
            arguments: arguments
        )
    }
}
