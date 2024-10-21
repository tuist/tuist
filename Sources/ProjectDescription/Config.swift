/// The configuration of your environment.
///
/// Tuist can be configured through a shared `Config.swift` manifest.
/// When Tuist is executed, it traverses up the directories to find a `Tuist` directory containing a `Config.swift` file.
/// Defining a configuration manifest is not required, but recommended to ensure a consistent behaviour across all the projects
/// that are part of the repository.
///
/// The example below shows a project that has a global `Config.swift` file that will be used when Tuist is run from any of the
/// subdirectories:
///
/// ```bash
/// /Workspace.swift
/// /Tuist/Config.swift # Configuration manifest
/// /Framework/Project.swift
/// /App/Project.swift
/// ```
///
/// That way, when executing Tuist in any of the subdirectories, it will use the shared configuration.
///
/// The snippet below shows an example configuration manifest:
///
/// ```swift
/// import ProjectDescription
///
/// let config = Config(
///     compatibleXcodeVersions: ["14.2"],
///     swiftVersion: "5.9.0"
/// )
/// ```
public struct Config: Codable, Equatable, Sendable {
    /// Generation options.
    public let generationOptions: GenerationOptions

    /// Install options.
    public let installOptions: InstallOptions

    /// Set the versions of Xcode that the project is compatible with.
    public let compatibleXcodeVersions: CompatibleXcodeVersions

    /// List of `Plugin`s used to extend Tuist.
    public let plugins: [PluginLocation]

    /// Cloud configuration.
    public let cloud: Cloud?

    /// The full project handle such as tuist-org/tuist.
    public let fullHandle: String?

    /// The base URL that points to the Tuist server.
    public let url: String

    /// The Swift tools versions that will be used by Tuist to fetch external dependencies.
    /// If `nil` is passed then Tuist will use the environment’s version.
    /// - Note: This **does not** control the `SWIFT_VERSION` build setting in regular generated projects, for this please use
    /// `Project.settings`
    /// or `Target.settings` as needed.
    public let swiftVersion: Version?

    /// Creates a tuist configuration.
    ///
    /// - Parameters:
    ///   - compatibleXcodeVersions: List of Xcode versions the project is compatible with.
    ///   - cloud: Cloud configuration.
    ///   - swiftVersion: The version of Swift that will be used by Tuist.
    ///   - plugins: A list of plugins to extend Tuist.
    ///   - generationOptions: List of options to use when generating the project.
    ///   - installOptions: List of options to use when running `tuist install`.
    public init(
        compatibleXcodeVersions: CompatibleXcodeVersions = .all,
        cloud: Cloud? = nil,
        fullHandle: String? = nil,
        url: String = "https://cloud.tuist.io",
        swiftVersion: Version? = nil,
        plugins: [PluginLocation] = [],
        generationOptions: GenerationOptions = .options(),
        installOptions: InstallOptions = .options()
    ) {
        self.compatibleXcodeVersions = compatibleXcodeVersions
        self.plugins = plugins
        self.generationOptions = generationOptions
        self.installOptions = installOptions
        self.cloud = cloud
        self.fullHandle = fullHandle
        self.url = url
        self.swiftVersion = swiftVersion
        dumpIfNeeded(self)
    }
}
