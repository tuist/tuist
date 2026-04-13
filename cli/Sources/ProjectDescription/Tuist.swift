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
        public static func cache(upload: Bool = true) -> Self {
            Cache(upload: upload)
        }
    }

    /// The HTTP proxy Tuist uses when talking to the Tuist server and related services.
    ///
    /// Use this to route Tuist's network traffic through a corporate HTTP proxy. Three modes
    /// are supported:
    ///
    /// - ``none`` (default): Tuist makes requests directly.
    /// - ``environmentVariable(_:)``: Tuist reads the proxy URL from an environment variable,
    ///   defaulting to `HTTPS_PROXY`. Pass a different name (e.g. `"HTTP_PROXY"` or a
    ///   custom variable) to read somewhere else.
    /// - ``url(_:)``: Tuist uses the proxy URL you pass directly. Include credentials inline
    ///   if the proxy requires authentication: `http://user:password@proxy.corp:8080`.
    public enum Proxy: Codable, Equatable, Sendable {
        /// No proxy. Tuist makes direct connections.
        case none

        /// Read the proxy URL from the named environment variable.
        ///
        /// - Parameter name: The environment variable to read. Defaults to `"HTTPS_PROXY"`,
        ///   which matches the convention used by `curl`, `git`, and most developer tools.
        case environmentVariable(String = "HTTPS_PROXY")

        /// Use the given proxy URL directly.
        ///
        /// - Parameter url: The proxy URL, e.g. `http://proxy.corp:8080`. Credentials can be
        ///   encoded inline as `http://user:password@proxy.corp:8080`.
        case url(String)
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

    /// The HTTP proxy Tuist routes its network traffic through. Defaults to ``Proxy/none``.
    public let proxy: Proxy

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
        cache = .cache()
        self.url = url
        proxy = .none
        dumpIfNeeded(self)
    }

    public init(
        fullHandle: String? = nil,
        inspectOptions: InspectOptions = .options(),
        cache: Cache = .cache(),
        url: String = "https://tuist.dev",
        proxy: Proxy = .none,
        project: TuistProject
    ) {
        self.project = project
        self.fullHandle = fullHandle
        self.inspectOptions = inspectOptions
        self.cache = cache
        self.url = url
        self.proxy = proxy
        dumpIfNeeded(self)
    }
}

extension Tuist.Proxy: ExpressibleByStringLiteral {
    /// Lets users write a proxy URL as a bare string literal in `Tuist.swift`:
    ///
    /// ```swift
    /// let tuist = Tuist(proxy: "http://proxy.corp:8080", project: .tuist())
    /// ```
    ///
    /// Equivalent to ``url(_:)``. Use the explicit cases when you need
    /// ``environmentVariable(_:)``.
    public init(stringLiteral value: String) {
        self = .url(value)
    }
}

extension Tuist.Proxy {
    private enum CodingKeys: String, CodingKey {
        case kind
        case value
    }

    private enum Kind: String, Codable {
        case none
        case environmentVariable
        case url
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .none:
            self = .none
        case .environmentVariable:
            let value = try container.decode(String.self, forKey: .value)
            self = .environmentVariable(value)
        case .url:
            let value = try container.decode(String.self, forKey: .value)
            self = .url(value)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .none:
            try container.encode(Kind.none, forKey: .kind)
        case let .environmentVariable(name):
            try container.encode(Kind.environmentVariable, forKey: .kind)
            try container.encode(name, forKey: .value)
        case let .url(url):
            try container.encode(Kind.url, forKey: .kind)
            try container.encode(url, forKey: .value)
        }
    }
}
