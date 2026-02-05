/// The configuration of your environment.
///
/// Tuist can be configured through a shared `Tuist.swift` manifest.
/// When Tuist is executed, it traverses up the directories to find `Tuist.swift` file.
/// Defining a configuration manifest is not required, but recommended to ensure a consistent behaviour across all the projects
/// that are part of the repository.
///
/// The example below shows a project that has a global `Tuist.swift` file that will be used when Tuist is run from any of the
/// subdirectories:
///
/// ```bash
/// /Workspace.swift
/// /Tuist.swift # Configuration manifest
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
/// let tuist = Config(project: .tuist(generationOptions: .options(additionalPackageResolutionArguments: ["--some-argument"])))
///
/// ```
public typealias Config = Tuist

public struct Tuist: Codable, Equatable, Sendable {
    /// Options for configuring the Xcode Cache behavior.
    public struct Cache: Codable, Equatable, Sendable {
        /// When `true` (default), the local proxy uploads artifacts to the remote cache.
        /// Set to `false` for read-only mode (downloads only, no uploads).
        public let upload: Bool

        /// Creates cache options.
        /// - Parameter upload: Whether to upload artifacts to the remote cache. Defaults to `true`.
        public static func options(upload: Bool = true) -> Self {
            Cache(upload: upload)
        }
    }

    /// Configures the project Tuist will interact with.
    /// When no project is provided, Tuist defaults to the workspace or project in the current directory.
    public let project: TuistProject

    /// The full project handle such as tuist-org/tuist.
    public let fullHandle: String?

    /// The options to use when running `tuist inspect`.
    public let inspectOptions: InspectOptions

    /// The Xcode Cache configuration.
    public let cache: Cache

    /// The base URL that points to the Tuist server.
    public let url: String

    /// Creates a tuist configuration.
    ///
    /// - Parameters:
    ///   - compatibleXcodeVersions: List of Xcode versions the project is compatible with.
    ///   - cloud: Cloud configuration.
    ///   - swiftVersion: The version of Swift that will be used by Tuist.
    ///   - plugins: A list of plugins to extend Tuist.
    ///   - generationOptions: List of options to use when generating the project.
    ///   - installOptions: List of options to use when running `tuist install`.
    @available(
        *,
        deprecated,
        message: "Use the new .init(project: .tuist(...)) that nests the property-related attributes into project."
    )
    public init(
        compatibleXcodeVersions: CompatibleXcodeVersions = .all,
        cloud: Cloud? = nil,
        fullHandle: String? = nil,
        url: String = "https://tuist.dev",
        swiftVersion: Version? = nil,
        plugins: [PluginLocation] = [],
        generationOptions: GenerationOptions = .options(),
        inspectOptions: InspectOptions = .options(),
        installOptions: InstallOptions = .options()
    ) {
        let fullHandle = cloud?.projectId ?? fullHandle
        let url = cloud?.url ?? url
        var generationOptions = generationOptions
        if let cloud {
            generationOptions.optionalAuthentication = cloud.options.contains(.optional)
        }

        project = TuistProject.tuist(
            compatibleXcodeVersions: compatibleXcodeVersions,
            swiftVersion: swiftVersion,
            plugins: plugins,
            generationOptions: generationOptions,
            installOptions: installOptions
        )
        self.fullHandle = fullHandle
        self.inspectOptions = inspectOptions
        cache = .options()
        self.url = url
        dumpIfNeeded(self)
    }

    public init(
        fullHandle: String? = nil,
        inspectOptions: InspectOptions = .options(),
        cache: Cache = .options(),
        url: String = "https://tuist.dev",
        project: TuistProject
    ) {
        self.project = project
        self.fullHandle = fullHandle
        self.inspectOptions = inspectOptions
        self.cache = cache
        self.url = url
        dumpIfNeeded(self)
    }
}
