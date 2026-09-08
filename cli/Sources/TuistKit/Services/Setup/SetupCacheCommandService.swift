import FileSystem
import Foundation
import Path
import struct TSCUtility.Version
import TuistAlert
import TuistConfigLoader
import TuistConstants
import TuistCore
import TuistEnvironment
import TuistGit
import TuistLaunchctl
import TuistLoader
import TuistLogging
import TuistServer
import TuistSupport

enum SetupCacheCommandServiceError: Equatable, LocalizedError {
    case missingFullHandle
    case notAuthenticated
    case cacheDaemonNotReady(label: String, socketPath: String, logPath: String)
    case registryNotReplaced(String, Int32)
    case registryNotLocked(String, Int32)
    case uploadPolicyRequiresProxy

    var errorDescription: String? {
        switch self {
        case .missingFullHandle:
            return
                "The 'Tuist.swift' file is missing a fullHandle. See how to set up a Tuist project at: https://tuist.dev/en/docs/guides/server/accounts-and-projects#projects"
        case .notAuthenticated:
            return
                "You must be authenticated to set up the cache. Run `tuist auth login` (or set the `TUIST_TOKEN` environment variable) and run `tuist setup cache` again."
        case let .cacheDaemonNotReady(label, socketPath, logPath):
            return
                "The Xcode cache daemon '\(label)' did not start listening at \(socketPath), so its launch agent was stopped. Check the daemon log at \(logPath), address the reported error, and run `tuist setup cache` again."
        case let .registryNotReplaced(path, code):
            return "Could not update the cache proxy's registry at \(path) (errno \(code))."
        case let .registryNotLocked(path, code):
            return "Could not lock the cache proxy's registry at \(path) (errno \(code))."
        case .uploadPolicyRequiresProxy:
            return
                "The upload policy is read from the cache proxy's registry, and this machine runs the per-project cache daemon instead (`TUIST_FEATURE_FLAG_KURA` is off). Change `xcodeCache(upload:)` in 'Tuist.swift' and run `tuist setup cache` again."
        }
    }
}

/// Which way `tuist setup cache --upload-policy` moves a project's recorded
/// Xcode cache upload policy.
///
/// Not a `Bool` on the command line: the flag stands in for `xcodeCache(upload:)`
/// for one machine, and `--upload-policy disabled` says in a CI file what
/// `--upload-policy false` would leave the reader to work out.
enum XcodeCacheUploadPolicy: String, CaseIterable, Sendable {
    case enabled
    case disabled

    var upload: Bool { self == .enabled }
}

struct SetupCacheCommandService {
    private let launchAgentService: LaunchAgentServicing
    private let configLoader: ConfigLoading
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let serverAuthenticationController: ServerAuthenticationControlling
    private let manifestLoader: ManifestLoading
    private let sourcesRegistry: CacheSourcesRegistry
    private let getProjectService: GetProjectServicing
    private let gitController: GitControlling
    private let cacheSocketService: CacheSocketServicing
    private let cacheDaemonStartupTimeout: Duration

    init(
        launchAgentService: LaunchAgentServicing = LaunchAgentService(),
        configLoader: ConfigLoading = ConfigLoader(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        serverAuthenticationController: ServerAuthenticationControlling = ServerAuthenticationController(),
        manifestLoader: ManifestLoading = ManifestLoader.current,
        fileSystem: FileSysteming = FileSystem(),
        getProjectService: GetProjectServicing = GetProjectService(),
        gitController: GitControlling = GitController(),
        cacheSocketService: CacheSocketServicing = CacheSocketService(),
        cacheDaemonStartupTimeout: Duration = .seconds(10)
    ) {
        self.launchAgentService = launchAgentService
        self.configLoader = configLoader
        self.serverEnvironmentService = serverEnvironmentService
        self.serverAuthenticationController = serverAuthenticationController
        self.manifestLoader = manifestLoader
        sourcesRegistry = CacheSourcesRegistry(fileSystem: fileSystem)
        self.getProjectService = getProjectService
        self.gitController = gitController
        self.cacheSocketService = cacheSocketService
        self.cacheDaemonStartupTimeout = cacheDaemonStartupTimeout
    }

    /// The project's default branch, which is what a trunk-scoped cache snapshot is
    /// anchored to. Best-effort: a setup that cannot reach the server still installs
    /// a working cache, and an unscoped snapshot is what this branch improves on
    /// rather than a regression.
    private func trunkBranch(fullHandle: String, serverURL: URL) async -> String? {
        do {
            return try await getProjectService.getProject(fullHandle: fullHandle, serverURL: serverURL)
                .defaultBranch
        } catch {
            Logger.current.debug(
                "Could not resolve \(fullHandle)'s default branch for the cache proxy: \(error). Its snapshot will not be trunk-scoped."
            )
            return nil
        }
    }

    /// The branch to record for a CI checkout. Only this command runs inside the
    /// job and can see it: the proxy is a launchd agent and does not inherit the
    /// job's environment, and a CI checkout's HEAD is detached, so nothing it
    /// could read from the repository would answer either.
    ///
    /// `nil` off CI on purpose, which leaves a developer's publishes untagged and
    /// therefore outside the trunk view. CI is the only publisher that view is
    /// built from, so it is the only one whose branch has to be right.
    private func ciBranch(sourceRoot: AbsolutePath) async -> String? {
        guard Environment.current.isCI else { return nil }
        do {
            return try await gitController.gitInfo(workingDirectory: sourceRoot).branch
        } catch {
            Logger.current.debug(
                "Could not resolve the CI branch for the cache proxy: \(error). Publishes from this job will be untagged."
            )
            return nil
        }
    }

    /// Records a `RegisteredSource` for this project in the proxy's sources
    /// registry.
    ///
    /// Upserts, so setting up a second project does not clobber the first.
    private func registerSource(
        fullHandle: String,
        trunk: String?,
        branch: String?,
        upload: Bool
    ) async throws {
        try await sourcesRegistry.update(fullHandle: fullHandle) { _ in
            RegisteredSource(trunk: trunk, branch: branch, upload: upload)
        }
    }

    /// Rewrites nothing but this project's upload policy in the proxy's sources
    /// registry, leaving the launch agent running.
    ///
    /// `Proxy::upload_enabled` re-reads the registry on a fifteen second memo, and
    /// every publication from both lanes and from the background sweeper passes
    /// through it, so the file is the whole mechanism. Reinstalling the agent to
    /// change one boolean would tear down and bootstrap the machine's only cache
    /// proxy for a change it never sees.
    ///
    /// The trunk and the CI branch are carried over rather than re-resolved. Neither
    /// is a policy decision: the trunk is the server's answer to a question this
    /// command is not asking, and the branch is what the setup that ran inside the
    /// CI job saw. Re-resolving them would put a server round trip and a git call in
    /// front of a local file write whose only outcomes are keeping them or losing
    /// them.
    private func setUploadPolicy(
        fullHandle: String,
        policy: XcodeCacheUploadPolicy,
        configuredUpload: Bool
    ) async throws {
        // The registry is the machine-wide proxy's file and nobody else's. On the
        // legacy per-project daemon the policy is a `--no-upload` launchd argument,
        // so writing it here would report success over a lane that keeps publishing.
        guard ClientFeatureFlags.contains("kura") else {
            throw SetupCacheCommandServiceError.uploadPolicyRequiresProxy
        }

        try await sourcesRegistry.update(fullHandle: fullHandle) { existing in
            RegisteredSource(trunk: existing?.trunk, branch: existing?.branch, upload: policy.upload)
        }

        // Enabling is not the mirror image of disabling. Disabling holds on its own,
        // because the proxy gate covers every publication whatever the build settings
        // say. Enabling only lifts the proxy's half: `tuist generate` bakes
        // `xcodeCache(upload: false)` into the project as `-cas-plugin-option
        // tuist-upload=false`, and the plugin's own gate keeps withholding Swift
        // outputs until the project is regenerated. Left unsaid, that is a flip
        // someone believes took and half of which did not.
        if policy == .enabled, !configuredUpload {
            AlertController.current.warning(
                "'Tuist.swift' still sets `xcodeCache(upload: false)`, which `tuist generate` bakes into generated projects as a build setting the cache plugin gates on by itself. Swift compilations keep withholding their outputs until the project is regenerated with `xcodeCache(upload: true)`. C, Objective-C and precompiled modules publish from now on."
            )
        }

        AlertController.current.success(
            .alert(
                "Xcode cache uploads are now \(policy.rawValue) for \(fullHandle)",
                takeaways: [
                    "The cache proxy picks this up within 15 seconds; its launch agent was left running",
                    "The policy is recorded per machine, so it covers every build of \(fullHandle) here",
                ]
            )
        )
    }

    private func ensureCacheDaemonIsListening(label: String, socketPath: AbsolutePath) async throws {
        if await cacheSocketService.waitUntilListening(
            at: socketPath,
            timeout: cacheDaemonStartupTimeout
        ) {
            return
        }

        Logger.current.debug(
            "The Xcode cache daemon did not start listening at \(socketPath.pathString). Restarting \(label) once."
        )
        do {
            try await launchAgentService.restartLaunchAgent(label: label)
            if await cacheSocketService.waitUntilListening(
                at: socketPath,
                timeout: cacheDaemonStartupTimeout
            ) {
                return
            }
        } catch {
            Logger.current.debug("Could not restart \(label): \(error.localizedDescription)")
        }

        try? await launchAgentService.teardownLaunchAgent(
            label: label,
            plistFileName: "\(label).plist"
        )
        let logPath = Environment.current.stateDirectory.appending(component: "\(label).stderr.log")
        throw SetupCacheCommandServiceError.cacheDaemonNotReady(
            label: label,
            socketPath: socketPath.pathString,
            logPath: logPath.pathString
        )
    }

    func run(
        path: String?,
        uploadPolicy: XcodeCacheUploadPolicy? = nil
    ) async throws {
        let path = try await Environment.current.pathRelativeToWorkingDirectory(path)
        let config = try await configLoader.loadConfig(path: path)

        guard let fullHandle = config.fullHandle else {
            throw SetupCacheCommandServiceError.missingFullHandle
        }

        // Before anything that authenticates or reaches the server. A policy flip
        // rewrites one field of a local file the proxy already reads; a credential
        // it does not need is a credential that can fail it, which is exactly the
        // read-scoped PR lane the flip exists for.
        if let uploadPolicy {
            try await setUploadPolicy(
                fullHandle: fullHandle,
                policy: uploadPolicy,
                configuredUpload: config.xcodeCache.upload
            )
            return
        }

        let serverURL = try serverEnvironmentService.url(configServerURL: config.url)

        // Fail fast when the user is not authenticated. Otherwise we would install a
        // LaunchAgent whose `cache-proxy` immediately exits (cleanly) for lack of
        // credentials, leaving setup looking successful while no proxy is running.
        guard try await serverAuthenticationController.authenticationToken(serverURL: serverURL) != nil else {
            throw SetupCacheCommandServiceError.notAuthenticated
        }

        // The `kura` client feature flag selects the machine-wide CAS proxy +
        // plugin. It is on unless `TUIST_FEATURE_FLAG_KURA` is set to a falsey
        // value, which puts the machine back on the legacy per-project cache
        // daemon.
        let kuraEnabled = ClientFeatureFlags.contains("kura")
        if kuraEnabled {
            // Register BEFORE starting the proxy. The proxy
            // prefetches a snapshot for every instance it already knows as soon as
            // it boots, and it keys that snapshot by instance alone: if it starts
            // first, an upgraded machine prefetches an unscoped view and keeps
            // serving it until the next full refresh, however promptly the mapping
            // lands afterwards.
            try await registerSource(
                fullHandle: fullHandle,
                trunk: await trunkBranch(fullHandle: fullHandle, serverURL: serverURL),
                branch: await ciBranch(sourceRoot: path),
                upload: config.xcodeCache.upload
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
            // Resolved before the log call: `Logger.info` takes an autoclosure,
            // which can't await.
            let prefixMapping = await prefixMappingInstructions()
            Logger.current.info(
                """
                Xcode Cache setup is almost complete!

                For projects not generated by Tuist, set these build settings in the Xcode projects you want to cache:
                COMPILATION_CACHE_ENABLE_CACHING=YES
                COMPILATION_CACHE_ENABLE_PLUGIN=YES
                COMPILATION_CACHE_PLUGIN_PATH=<path to libtuist_cas_plugin.dylib>
                COMPILATION_CACHE_REMOTE_SERVICE_PATH=\(proxySocketPath)
                COMPILATION_CACHE_ENABLE_DIAGNOSTIC_REMARKS=YES
                OTHER_SWIFT_FLAGS=$(inherited) -cas-plugin-option tuist-instance=\(fullHandle)\(prefixMapping)

                `COMPILATION_CACHE_REMOTE_SERVICE_PATH` is what lets C, Objective-C and precompiled modules be shared too. Without it only Swift is shared, and a machine with a cold cache recompiles the rest.

                `COMPILATION_CACHE_ENABLE_PLUGIN`, `COMPILATION_CACHE_PLUGIN_PATH` and `COMPILATION_CACHE_REMOTE_SERVICE_PATH` are not directly exposed by Xcode; add them as user-defined build settings. See the docs for the plugin path: https://tuist.dev/en/docs/guides/features/cache/xcode-cache
                """
            )
        } else {
            let socketPath = Environment.current.cacheSocketPathString(for: fullHandle)
            let prefixMapping = await prefixMappingInstructions()
            Logger.current.info(
                """
                Xcode Cache setup is almost complete!

                For projects not generated by Tuist, set these build settings in the Xcode projects you want to cache:
                COMPILATION_CACHE_ENABLE_CACHING=YES
                COMPILATION_CACHE_REMOTE_SERVICE_PATH=\(socketPath)
                COMPILATION_CACHE_ENABLE_PLUGIN=YES
                COMPILATION_CACHE_ENABLE_DIAGNOSTIC_REMARKS=YES\(prefixMapping)

                `COMPILATION_CACHE_REMOTE_SERVICE_PATH` and `COMPILATION_CACHE_ENABLE_PLUGIN` are not directly exposed by Xcode; add them as user-defined build settings.
                """
            )
        }
    }

    /// The prefix-mapping settings to append to the manual build-setting
    /// instructions, or an empty string on Xcode versions that don't implement
    /// them.
    ///
    /// Without these, a compilation-cache key embeds absolute paths — most
    /// importantly DerivedData's — so the same compilation caches under a
    /// different key on every machine and artifacts can't be reused between
    /// developers or between local and CI. Xcode 27 (Swift 6.4) is the first
    /// version whose build system implements the source/build directory mappings,
    /// and Apple ships them off by default (staged adoption), so they have to be
    /// opted into. `tuist generate` sets them automatically; this is the
    /// equivalent for projects Tuist doesn't generate.
    private func prefixMappingInstructions() async -> String {
        guard let version = try? await XcodeController.current.selectedVersion(),
              version >= Version(27, 0, 0)
        else { return "" }
        return """

        SWIFT_ENABLE_PREFIX_MAPPING=YES
        SWIFT_ENABLE_PROJECT_PREFIX_MAPPING=YES
        CLANG_ENABLE_PREFIX_MAPPING=YES
        CLANG_ENABLE_PROJECT_PREFIX_MAPPING=YES

        The four *_PREFIX_MAPPING settings make cache keys independent of where the project and DerivedData live, so artifacts are reusable across machines and CI. They are Xcode 27+ only, are not exposed by Xcode (add them as user-defined build settings), and enabling them changes every cache key — the next build re-populates the cache from cold, once.
        """
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
        // Without this the agent falls back to `<socket>.registry` and never reads
        // the sources file written beside the override above.
        if let registry = Environment.current.variables["TUIST_CAS_PROXY_REGISTRY"] {
            environmentVariables["TUIST_CAS_PROXY_REGISTRY"] = registry
        }
        // The proxy's diagnostics (the `incomplete closure` shapes and the
        // periodic stats line) are written only to the file this variable names,
        // never to stdout or stderr, so without forwarding it there is no way to
        // turn them on for a proxy running under launchd.
        if let logPath = Environment.current.variables["TUIST_CAS_LOG"] {
            environmentVariables["TUIST_CAS_LOG"] = logPath
        } else if Environment.current.isCI {
            // The counters that tell the CAS failure shapes apart are written ONLY
            // to this file, so a variable nobody knew to set is off during every
            // incident that needs it. What makes defaulting it acceptable is that
            // the plugin bounds the file, truncating it in place past a cap.
            //
            // Only the PROXY's half is defaulted here. The plugin resolves the same
            // path itself (`default_log_path`), which is what covers the compiler
            // frontends however `xcodebuild` was invoked, including workflows that
            // generate and then drive `xcodebuild` or Fastlane directly. The proxy
            // cannot do the same because launchd hands it no CI markers to key on.
            //
            // CI only, and deliberately not on developer machines: the proxy there
            // is a long-lived LaunchAgent, so even a bounded file is state we would
            // create on every `tuist setup cache` for a reader who never asked for
            // it. A CI machine is ephemeral and the job bounds it.
            environmentVariables["TUIST_CAS_LOG"] = Environment.current.casLogPath().pathString
        }
        // Trunk ingestion pays for itself only where the machine can warm the CAS
        // BEFORE a build: it pulls the trunk closure in the background so the next
        // build finds it local. CI has no such window. The proxy and the build
        // start together, so ingestion would race the build it is meant to help
        // and compete for the bandwidth that build's own demand fetches need. Our
        // runners have less use for it still: their CAS arrives warm on an
        // attached volume, which is the mechanism there.
        //
        // `keys` and not `0`: the key cache is one round trip and orders of
        // magnitude lighter than the bytes, and it is what gives a cold CI
        // machine its breadth. Turning it off too would make every resolve a
        // per-key round trip.
        if Environment.current.isCI {
            environmentVariables["TUIST_CAS_PREFETCH"] = "keys"
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
        try await ensureCacheDaemonIsListening(
            label: label,
            socketPath: Environment.current.casProxySocketPath()
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
        try await ensureCacheDaemonIsListening(
            label: label,
            socketPath: Environment.current.cacheSocketPath(for: fullHandle)
        )
    }
}
