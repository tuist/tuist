public enum TuistProject: Codable, Equatable, Sendable {
    /// Creates a configuration for a Tuist project.
    ///
    /// - Parameters:
    ///   - compatibleXcodeVersions: List of Xcode versions the project is compatible with.
    ///   - swiftVersion: The version of Swift that will be used by Tuist.
    ///   - plugins: A list of plugins to extend Tuist.
    ///   - generationOptions: List of options to use when generating the project.
    ///   - installOptions: List of options to use when running `tuist install`.
    case tuist(
        compatibleXcodeVersions: CompatibleXcodeVersions = .all,
        swiftVersion: Version? = nil,
        plugins: [PluginLocation] = [],
        generationOptions: Tuist.GenerationOptions = .options(),
        installOptions: Tuist.InstallOptions = .options()
    )
    case xcode(TuistProjectXcodeOptions = .options())
}

/// They represent options to configure the integration of Xcode with the Xcode project.
public struct TuistProjectXcodeOptions: Codable, Equatable, Sendable {
    private init() {}
    public static func options() -> TuistProjectXcodeOptions {
        return TuistProjectXcodeOptions()
    }
}
