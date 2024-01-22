import Foundation

/// An action that profiles the built products.
public struct ProfileAction: Equatable, Codable {
    /// Indicates the build configuration the product should be profiled with.
    public var configuration: ConfigurationName = .release

    /// A list of actions that are executed before starting the profile process.
    public var preActions: [ExecutionAction] = []

    /// A list of actions that are executed after the profile process.
    public var postActions: [ExecutionAction] = []

    /// The name of the executable or target to profile.
    public var executable: TargetReference? = nil

    /// Command line arguments passed on launch and environment variables.
    public var arguments: Arguments? = nil
}
