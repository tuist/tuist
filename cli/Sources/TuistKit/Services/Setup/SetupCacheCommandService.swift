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
    private let fileSystem: FileSysteming
    private let getProjectService: GetProjectServicing

    init(
        launchAgentService: LaunchAgentServicing = LaunchAgentService(),
        configLoader: ConfigLoading = ConfigLoader(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        serverAuthenticationController: ServerAuthenticationControlling = ServerAuthenticationController(),
        manifestLoader: ManifestLoading = ManifestLoader.current,
        fileSystem: FileSysteming = FileSystem(),
        getProjectService: GetProjectServicing = GetProjectService()
    ) {
        self.launchAgentService = launchAgentService
        self.configLoader = configLoader
        self.serverEnvironmentService = serverEnvironmentService
        self.serverAuthenticationController = serverAuthenticationController
        self.manifestLoader = manifestLoader
        self.fileSystem = fileSystem
        self.getProjectService = getProjectService
    }

    /// The project's default branch, which is what a trunk-scoped cache snapshot
    /// is anchored to. Best-effort: a setup that cannot reach the server still
    /// installs a working cache, and the proxy falls back to deriving the trunk
    /// from the checkout's `origin/HEAD`.
    private func trunkBranch(fullHandle: String, serverURL: URL) async -> String? {
        do {
            return try await getProjectService.getProject(fullHandle: fullHandle, serverURL: serverURL)
                .defaultBranch
        } catch {
            Logger.current.debug(
                "Could not resolve \(fullHandle)'s default branch for the cache proxy: \(error). The proxy will derive the trunk from the checkout instead."
            )
            return nil
        }
    }

    /// Records `fullHandle -> sourceRoot, trunk` in the proxy's sources registry
    /// (`<state>/cas-proxy.sock.registry.sources`, honoring the same
    /// `TUIST_CAS_PROXY_REGISTRY` override the proxy reads). Two things the proxy
    /// cannot know on its own:
    ///
    /// - The source root, from which it derives the branch of every publish live
    ///   off this repo's git HEAD. Nothing branch-specific is baked into a build
    ///   setting, which would enter the compiler's cache key and split the cache
    ///   per branch.
    /// - The trunk, which is the *project's* configured default branch and hence
    ///   a server-side decision. The proxy would otherwise have to guess it from
    ///   the local clone's `origin/HEAD`, which is a property of how the machine
    ///   cloned rather than of the project.
    ///
    /// Upserts, so setting up a second project does not clobber the first.
    private func registerSourceRoot(
        fullHandle: String,
        sourceRoot: AbsolutePath,
        trunk: String?
    ) async throws {
        let sourcesPath: AbsolutePath
        if let registry = Environment.current.variables["TUIST_CAS_PROXY_REGISTRY"] {
            sourcesPath = try AbsolutePath(validating: registry + ".sources")
        } else {
            sourcesPath = Environment.current.stateDirectory
                .appending(component: "cas-proxy.sock.registry.sources")
        }

        // instance -> (source root, trunk). The trunk column is optional: a
        // registry written before this shipped, or by a setup that could not
        // reach the server, still parses and leaves the proxy on its git-derived
        // fallback.
        var entries: [String: (root: String, trunk: String?)] = [:]
        if try await fileSystem.exists(sourcesPath) {
            let contents = try await fileSystem.readTextFile(at: sourcesPath)
            for line in contents.split(separator: "\n") {
                let parts = line.split(separator: "\t", maxSplits: 2).map(String.init)
                if parts.count >= 2 {
                    entries[parts[0]] = (root: parts[1], trunk: parts.count > 2 ? parts[2] : nil)
                }
            }
        }
        entries[fullHandle] = (root: sourceRoot.pathString, trunk: trunk)

        let body = entries.sorted { $0.key < $1.key }
            .map { key, value in
                if let trunk = value.trunk, !trunk.isEmpty {
                    return "\(key)\t\(value.root)\t\(trunk)"
                }
                return "\(key)\t\(value.root)"
            }
            .joined(separator: "\n") + "\n"
        if try await !fileSystem.exists(sourcesPath.parentDirectory, isDirectory: true) {
            try await fileSystem.makeDirectory(at: sourcesPath.parentDirectory)
        }
        if try await fileSystem.exists(sourcesPath) {
            try await fileSystem.remove(sourcesPath)
        }
        try await fileSystem.writeText(body, at: sourcesPath)
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
            // Register the source root BEFORE starting the proxy. The proxy
            // prefetches a snapshot for every instance it already knows as soon as
            // it boots, and it keys that snapshot by instance alone: if it starts
            // first, an upgraded machine prefetches an unscoped view and keeps
            // serving it until the next full refresh, however promptly the mapping
            // lands afterwards.
            try await registerSourceRoot(
                fullHandle: fullHandle,
                sourceRoot: path,
                trunk: await trunkBranch(fullHandle: fullHandle, serverURL: serverURL)
            )
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
            let proxySocketPath = Environment.current.casProxySocketPathString()
            Logger.current.info(
                """
                Xcode Cache setup is almost complete!

                For projects not generated by Tuist, set these build settings in the Xcode projects you want to cache:
                COMPILATION_CACHE_ENABLE_CACHING=YES
                COMPILATION_CACHE_ENABLE_PLUGIN=YES
                COMPILATION_CACHE_PLUGIN_PATH=<path to libtuist_cas_plugin.dylib>
                COMPILATION_CACHE_REMOTE_SERVICE_PATH=\(proxySocketPath)
                COMPILATION_CACHE_ENABLE_DIAGNOSTIC_REMARKS=YES
                OTHER_SWIFT_FLAGS=$(inherited) -cas-plugin-option tuist-instance=\(fullHandle)

                `COMPILATION_CACHE_REMOTE_SERVICE_PATH` is what lets C, Objective-C and precompiled modules be shared too. Without it only Swift is shared, and a machine with a cold cache recompiles the rest.

                `COMPILATION_CACHE_ENABLE_PLUGIN`, `COMPILATION_CACHE_PLUGIN_PATH` and `COMPILATION_CACHE_REMOTE_SERVICE_PATH` are not directly exposed by Xcode; add them as user-defined build settings. See the docs for the plugin path: https://tuist.dev/en/docs/guides/features/cache/xcode-cache
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
        // rather than a keychain session, seed it directly. `TUIST_TOKEN` is
        // forwarded alongside `TUIST_CAS_TOKEN` because the `cache-proxy` wrapper
        // gates on `ServerAuthenticationController.authenticationToken`, whose env
        // lookup reads `TUIST_TOKEN`/`TUIST_CONFIG_TOKEN` (not `TUIST_CAS_TOKEN`)
        // before the keychain — and under launchd on CI the keychain is empty, so
        // without this the wrapper exits cleanly and the proxy never starts.
        if let token = Environment.current.tuistVariables[Constants.EnvironmentVariables.token] {
            environmentVariables["TUIST_CAS_TOKEN"] = token
            environmentVariables[Constants.EnvironmentVariables.token] = token
        } else if let token = Environment.current.tuistVariables[Constants.EnvironmentVariables.deprecatedToken] {
            AlertController.current
                .warning("Use `TUIST_TOKEN` environment variable instead of `TUIST_CONFIG_TOKEN` to authenticate on the CI")
            environmentVariables["TUIST_CAS_TOKEN"] = token
            environmentVariables[Constants.EnvironmentVariables.token] = token
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
