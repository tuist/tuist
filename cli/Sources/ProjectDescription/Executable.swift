/// Represents the executable configuration for a scheme's launch or profile action.
public enum Executable: Equatable, Codable, Sendable {
    /// Presents the "Ask on Launch" dialog when running or profiling,
    /// allowing the user to choose the app to launch at runtime.
    case askOnLaunch

    /// Uses a specific target reference as the executable, or `nil` for the default.
    case executable(TargetReference?)
}
