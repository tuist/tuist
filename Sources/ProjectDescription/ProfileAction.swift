import Foundation

public struct ProfileAction: Equatable, Codable {
    public let configuration: ConfigurationName
    public let executable: TargetReference?
    public let arguments: Arguments?

    init(configuration: ConfigurationName = .release,
         executable: TargetReference? = nil,
         arguments: Arguments? = nil)
    {
        self.configuration = configuration
        self.executable = executable
        self.arguments = arguments
    }

    /// Initializes a profile action.
    /// - Parameters:
    ///   - configuration: Configuration to be used for profiling.
    ///   - executable: Profiled executable.
    ///   - arguments: Arguments to pass when launching the executable.
    /// - Returns: Initialized profile action.
    public static func profileAction(configuration: ConfigurationName = .release,
                                     executable: TargetReference? = nil,
                                     arguments: Arguments? = nil) -> ProfileAction
    {
        return ProfileAction(
            configuration: configuration,
            executable: executable,
            arguments: arguments
        )
    }
}
