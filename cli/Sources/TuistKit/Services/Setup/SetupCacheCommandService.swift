import FileSystem
import Foundation
import Path
import TuistAlert
import TuistConfigLoader
import TuistConstants
import TuistCore
import TuistEnvironment
import TuistLaunchctl
import TuistLoader
import TuistLogging
import TuistServer
import TuistSupport

enum SetupCacheCommandServiceError: Equatable, LocalizedError {
    case missingFullHandle
    case notAuthenticated

    var errorDescription: String? {
        switch self {
        case .missingFullHandle:
            return
                "The 'Tuist.swift' file is missing a fullHandle. See how to set up a Tuist project at: https://tuist.dev/en/docs/guides/server/accounts-and-projects#projects"
        case .notAuthenticated:
            return
                "You must be authenticated to set up the cache. Run `tuist auth login` (or set the `TUIST_TOKEN` environment variable) and run `tuist setup cache` again."
        }
    }
}

struct SetupCacheCommandService {
    /// A stable, version-independent path that `tuist setup cache` points at the
    /// compilation-cache plugin shipped with the current `tuist`. Projects set
    /// `COMPILATION_CACHE_PLUGIN_PATH` to this once; re-running `tuist setup cache`
    /// after a version bump repoints it, the same run that refreshes the proxy.
    static func compilationCachePluginLink() -> AbsolutePath {
        Environment.current.homeDirectory.appending(components: ".tuist", "libtuist_cas_plugin.dylib")
    }

    private let launchAgentService: LaunchAgentServicing
    private let configLoader: ConfigLoading
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let serverAuthenticationController: ServerAuthenticationControlling
    private let manifestLoader: ManifestLoading
    private let resourceLocator: ResourceLocating
    private let fileSystem: FileSysteming

    init(
        launchAgentService: LaunchAgentServicing = LaunchAgentService(),
        configLoader: ConfigLoading = ConfigLoader(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        serverAuthenticationController: ServerAuthenticationControlling = ServerAuthenticationController(),
        manifestLoader: ManifestLoading = ManifestLoader.current,
        resourceLocator: ResourceLocating = ResourceLocator(),
        fileSystem: FileSysteming = FileSystem()
    ) {
        self.launchAgentService = launchAgentService
        self.configLoader = configLoader
        self.serverEnvironmentService = serverEnvironmentService
        self.serverAuthenticationController = serverAuthenticationController
        self.manifestLoader = manifestLoader
        self.resourceLocator = resourceLocator
        self.fileSystem = fileSystem
    }

    /// Best-effort: symlink the stable plugin path at the dylib shipped with this
    /// `tuist`. Skips silently when the dylib is not present (e.g. a dev build),
    /// since the plugin path is only needed for non-generated Xcode projects.
    private func linkCompilationCachePlugin() async {
        do {
            guard let pluginPath = try await resourceLocator.casPlugin() else { return }
            let link = Self.compilationCachePluginLink()
            try await fileSystem.makeDirectory(at: link.parentDirectory)
            try? await fileSystem.remove(link)
            try await fileSystem.createSymbolicLink(from: link, to: pluginPath)
        } catch {
            Logger.current.debug("Could not link the compilation-cache plugin: \(error)")
        }
    }

    func run(
        path: String?
    ) async throws {
        let path = try await Environment.current.pathRelativeToWorkingDirectory(path)
        let config = try await configLoader.loadConfig(path: path)

        guard let fullHandle = config.fullHandle else {
            throw SetupCacheCommandServiceError.missingFullHandle
        }

        let serverURL = try serverEnvironmentService.url(configServerURL: config.url)

        // Fail fast when the user is not authenticated. Otherwise we would install a
        // LaunchAgent whose `cache-proxy` immediately exits (cleanly) for lack of
        // credentials, leaving setup looking successful while no proxy is running.
        guard try await serverAuthenticationController.authenticationToken(serverURL: serverURL) != nil else {
            throw SetupCacheCommandServiceError.notAuthenticated
        }

        let accountHandle = fullHandle.split(separator: "/").first.map(String.init)

        var programArguments = ["cache-proxy", "--url", serverURL.absoluteString]
        if let accountHandle {
            programArguments.append(contentsOf: ["--account", accountHandle])
        }

        var environmentVariables: [String: String] = [:]
        // The proxy fetches and refreshes its bearer itself by shelling out to
        // `tuist auth token`. On CI, where the credential is an environment
        // token rather than a keychain session, seed it directly.
        if let token = Environment.current.tuistVariables[Constants.EnvironmentVariables.token] {
            environmentVariables["TUIST_CAS_TOKEN"] = token
        } else if let token = Environment.current.tuistVariables[Constants.EnvironmentVariables.deprecatedToken] {
            AlertController.current
                .warning("Use `TUIST_TOKEN` environment variable instead of `TUIST_CONFIG_TOKEN` to authenticate on the CI")
            environmentVariables["TUIST_CAS_TOKEN"] = token
        }

        // The proxy runs as a launchd agent that does not inherit the caller's
        // environment. Request kura (REAPI) endpoints, and forward the client
        // feature flags so endpoint resolution matches the rest of the CLI.
        environmentVariables["TUIST_FEATURE_FLAG_KURA"] = "1"
        for (key, value) in ClientFeatureFlags.environmentVariables() {
            environmentVariables[key] = value
        }

        // Forward the cache-endpoint override. The runner-cache dispatch hands
        // runners the private-network cache as a hard TUIST_CACHE_ENDPOINT
        // override, which CacheURLStore honors when the proxy resolves its
        // endpoint at launch.
        if let cacheEndpoint = Environment.current.variables["TUIST_CACHE_ENDPOINT"] {
            environmentVariables["TUIST_CACHE_ENDPOINT"] = cacheEndpoint
        }

        // One proxy per machine, multiplexing every project by instance — not a
        // per-project daemon. Boot out any legacy per-project cache daemon so the
        // two do not both run.
        let legacyLabel = Environment.current.cacheLaunchAgentLabel(for: fullHandle)
        try? await launchAgentService.teardownLaunchAgent(
            label: legacyLabel,
            plistFileName: "\(legacyLabel).plist"
        )

        let label = Environment.current.casProxyLaunchAgentLabel()

        try await launchAgentService.setupLaunchAgent(
            label: label,
            plistFileName: "\(label).plist",
            programArguments: programArguments,
            environmentVariables: environmentVariables
        )

        await linkCompilationCachePlugin()

        if try await manifestLoader.hasRootManifest(at: path) {
            if let generationOptions = config.project.generatedProject?.generationOptions,
               generationOptions.enableCaching == true
            {
                AlertController.current.success(
                    .alert(
                        "Xcode Cache has been enabled 🎉",
                        takeaways: [
                            "Learn more in the \(.link(title: "Xcode cache docs", href: "https://tuist.dev/en/docs/guides/features/cache/xcode-cache"))",
                            "The cache proxy is running; `tuist generate` wires the compilation-cache plugin into your project automatically",
                        ]
                    )
                )
            } else {
                Logger.current.info(
                    """
                    Xcode Cache setup is almost complete!

                    To enable Xcode Cache for this project, set the enableCaching property in your Tuist.swift file to true:

                    let tuist = Tuist(
                        fullHandle: "\(fullHandle)",
                        project: .tuist(
                            generationOptions: .options(
                                enableCaching: true
                            )
                        )
                    )

                    The cache proxy is running; `tuist generate` will wire the compilation-cache plugin into your project.
                    """
                )
            }
        } else {
            Logger.current.info(
                """
                Xcode Cache setup is almost complete!

                The cache proxy is running. For projects not generated by Tuist, set the following build
                settings in the Xcode projects you want to use caching for:
                COMPILATION_CACHE_ENABLE_CACHING=YES
                COMPILATION_CACHE_ENABLE_PLUGIN=YES
                COMPILATION_CACHE_PLUGIN_PATH=\(Self.compilationCachePluginLink().pathString)

                Re-run `tuist setup cache` after upgrading Tuist to keep that path pointing at the matching plugin.
                """
            )
        }
    }
}
