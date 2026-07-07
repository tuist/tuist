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
    private let launchAgentService: LaunchAgentServicing
    private let configLoader: ConfigLoading
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let serverAuthenticationController: ServerAuthenticationControlling
    private let manifestLoader: ManifestLoading

    init(
        launchAgentService: LaunchAgentServicing = LaunchAgentService(),
        configLoader: ConfigLoading = ConfigLoader(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        serverAuthenticationController: ServerAuthenticationControlling = ServerAuthenticationController(),
        manifestLoader: ManifestLoading = ManifestLoader.current
    ) {
        self.launchAgentService = launchAgentService
        self.configLoader = configLoader
        self.serverEnvironmentService = serverEnvironmentService
        self.serverAuthenticationController = serverAuthenticationController
        self.manifestLoader = manifestLoader
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

        // The `kura` client feature flag selects the machine-wide CAS proxy +
        // plugin. Without it, accounts stay on the legacy per-project cache daemon
        // they rely on today, until they are migrated to kura.
        let kuraEnabled = ClientFeatureFlags.contains("kura")
        if kuraEnabled {
            try await installProxy(fullHandle: fullHandle, serverURL: serverURL)
        } else {
            try await installLegacyDaemon(
                fullHandle: fullHandle,
                serverURL: serverURL,
                upload: config.xcodeCache.upload
            )
        }

        if try await manifestLoader.hasRootManifest(at: path) {
            if let generationOptions = config.project.generatedProject?.generationOptions,
               generationOptions.enableCaching == true
            {
                AlertController.current.success(
                    .alert(
                        "Xcode Cache has been enabled 🎉",
                        takeaways: [
                            "Learn more in the \(.link(title: "Xcode cache docs", href: "https://tuist.dev/en/docs/guides/features/cache/xcode-cache"))",
                            "Xcode Cache is set up; `tuist generate` wires it into your project automatically",
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

                    Xcode Cache is set up; `tuist generate` will wire it into your project.
                    """
                )
            }
        } else if kuraEnabled {
            Logger.current.info(
                """
                Xcode Cache setup is almost complete!

                For projects not generated by Tuist, set these build settings in the Xcode projects you want to cache:
                COMPILATION_CACHE_ENABLE_CACHING=YES
                COMPILATION_CACHE_ENABLE_PLUGIN=YES
                COMPILATION_CACHE_PLUGIN_PATH=<path to libtuist_cas_plugin.dylib>
                COMPILATION_CACHE_ENABLE_DIAGNOSTIC_REMARKS=YES
                OTHER_SWIFT_FLAGS=$(inherited) -cas-plugin-option tuist-instance=\(fullHandle)

                `COMPILATION_CACHE_ENABLE_PLUGIN` and `COMPILATION_CACHE_PLUGIN_PATH` are not directly exposed by Xcode; add them as user-defined build settings. See the docs for the plugin path: https://tuist.dev/en/docs/guides/features/cache/xcode-cache
                """
            )
        } else {
            let socketPath = Environment.current.cacheSocketPathString(for: fullHandle)
            Logger.current.info(
                """
                Xcode Cache setup is almost complete!

                For projects not generated by Tuist, set these build settings in the Xcode projects you want to cache:
                COMPILATION_CACHE_ENABLE_CACHING=YES
                COMPILATION_CACHE_REMOTE_SERVICE_PATH=\(socketPath)
                COMPILATION_CACHE_ENABLE_PLUGIN=YES
                COMPILATION_CACHE_ENABLE_DIAGNOSTIC_REMARKS=YES

                `COMPILATION_CACHE_REMOTE_SERVICE_PATH` and `COMPILATION_CACHE_ENABLE_PLUGIN` are not directly exposed by Xcode; add them as user-defined build settings.
                """
            )
        }
    }

    /// Installs the machine-wide CAS proxy (kura path): one launchd agent that
    /// multiplexes every project on the machine by instance.
    private func installProxy(fullHandle: String, serverURL: URL) async throws {
        let accountHandle = fullHandle.split(separator: "/").first.map(String.init)

        var programArguments = ["cache-proxy", "--url", serverURL.absoluteString]
        if let accountHandle {
            programArguments.append(contentsOf: ["--account", accountHandle])
        }

        var environmentVariables: [String: String] = [:]
        // The proxy fetches and refreshes its bearer itself by shelling out to
        // `tuist auth token`. On CI, where the credential is an environment token
        // rather than a keychain session, seed it directly.
        if let token = Environment.current.tuistVariables[Constants.EnvironmentVariables.token] {
            environmentVariables["TUIST_CAS_TOKEN"] = token
        } else if let token = Environment.current.tuistVariables[Constants.EnvironmentVariables.deprecatedToken] {
            AlertController.current
                .warning("Use `TUIST_TOKEN` environment variable instead of `TUIST_CONFIG_TOKEN` to authenticate on the CI")
            environmentVariables["TUIST_CAS_TOKEN"] = token
        }

        // The proxy runs as a launchd agent that does not inherit the caller's
        // environment. Forward the client feature flags (including `kura`) so its
        // endpoint resolution matches the rest of the CLI.
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

        // One proxy per machine. Boot out any legacy per-project cache daemon so
        // the two do not both run.
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
    }

    /// Installs the legacy per-project CAS daemon (non-kura path): one launchd
    /// agent per project serving Xcode's compilation-cache gRPC protocol over the
    /// unix socket the generated `COMPILATION_CACHE_REMOTE_SERVICE_PATH` points at.
    private func installLegacyDaemon(fullHandle: String, serverURL: URL, upload: Bool) async throws {
        var programArguments = ["cache-start", fullHandle, "--url", serverURL.absoluteString]
        if !upload {
            programArguments.append("--no-upload")
        }

        var environmentVariables: [String: String] = [:]
        if let token = Environment.current.tuistVariables[Constants.EnvironmentVariables.token] {
            environmentVariables["TUIST_TOKEN"] = token
        } else if let token = Environment.current.tuistVariables[Constants.EnvironmentVariables.deprecatedToken] {
            AlertController.current
                .warning("Use `TUIST_TOKEN` environment variable instead of `TUIST_CONFIG_TOKEN` to authenticate on the CI")
            environmentVariables["TUIST_TOKEN"] = token
        }

        // The daemon runs as a launchd agent that does not inherit the caller's
        // environment. Forward the client feature flags for consistent behavior.
        for (key, value) in ClientFeatureFlags.environmentVariables() {
            environmentVariables[key] = value
        }
        if let cacheEndpoint = Environment.current.variables["TUIST_CACHE_ENDPOINT"] {
            environmentVariables["TUIST_CACHE_ENDPOINT"] = cacheEndpoint
        }

        // Boot out the machine-wide proxy so the two do not both run.
        let proxyLabel = Environment.current.casProxyLaunchAgentLabel()
        try? await launchAgentService.teardownLaunchAgent(
            label: proxyLabel,
            plistFileName: "\(proxyLabel).plist"
        )

        let label = Environment.current.cacheLaunchAgentLabel(for: fullHandle)
        try await launchAgentService.setupLaunchAgent(
            label: label,
            plistFileName: "\(label).plist",
            programArguments: programArguments,
            environmentVariables: environmentVariables
        )
    }
}
