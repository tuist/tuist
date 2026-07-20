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
    case registryNotReplaced(String, Int32)
    case registryNotLocked(String, Int32)

    var errorDescription: String? {
        switch self {
        case .missingFullHandle:
            return
                "The 'Tuist.swift' file is missing a fullHandle. See how to set up a Tuist project at: https://tuist.dev/en/docs/guides/server/accounts-and-projects#projects"
        case .notAuthenticated:
            return
                "You must be authenticated to set up the cache. Run `tuist auth login` (or set the `TUIST_TOKEN` environment variable) and run `tuist setup cache` again."
        case let .registryNotReplaced(path, code):
            return "Could not update the cache proxy's registry at \(path) (errno \(code))."
        case let .registryNotLocked(path, code):
            return "Could not lock the cache proxy's registry at \(path) (errno \(code))."
        }
    }
}

/// What setup knows about a project that the proxy cannot work out for itself
/// (see `load_sources` in cas-plugin).
///
/// The registry is a JSON object of instance -> this. JSON because we write it
/// and the proxy reads it from another language: a format each side hand-rolls
/// is one each side can drift on, and every value here is optional, which is the
/// shape a hand-rolled one gets wrong first.
private struct RegisteredSource: Codable {
    /// The project's configured default branch, which is a server-side decision.
    /// The proxy would otherwise have to guess it from the local clone's
    /// `origin/HEAD`, a property of how this machine cloned rather than of the
    /// project.
    let trunk: String?
    /// Recorded only on CI. See `ciBranch`.
    let branch: String?
    /// The project's `xcodeCache.upload`. The proxy is the only place that can
    /// enforce this: the plugin reads it as a compiler option, which reaches
    /// Swift, while the build system's Clang caching runs in its own process
    /// with no plugin options at all. Recorded here so one answer covers both.
    let upload: Bool

    init(trunk: String?, branch: String?, upload: Bool) {
        self.trunk = trunk
        self.branch = branch
        self.upload = upload
    }

    /// Hand-written rather than synthesized, so that an absent field means here
    /// what it means to the proxy. The synthesized one requires every
    /// non-optional, which would make this side reject a registry the proxy
    /// reads happily: the drift that using one format on both sides exists to
    /// prevent.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        trunk = try container.decodeIfPresent(String.self, forKey: .trunk)
        branch = try container.decodeIfPresent(String.self, forKey: .branch)
        // Nothing recorded is nothing to withhold (`uploads_by_default` there).
        upload = try container.decodeIfPresent(Bool.self, forKey: .upload) ?? true
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
    private let gitController: GitControlling

    init(
        launchAgentService: LaunchAgentServicing = LaunchAgentService(),
        configLoader: ConfigLoading = ConfigLoader(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        serverAuthenticationController: ServerAuthenticationControlling = ServerAuthenticationController(),
        manifestLoader: ManifestLoading = ManifestLoader.current,
        fileSystem: FileSysteming = FileSystem(),
        getProjectService: GetProjectServicing = GetProjectService(),
        gitController: GitControlling = GitController()
    ) {
        self.launchAgentService = launchAgentService
        self.configLoader = configLoader
        self.serverEnvironmentService = serverEnvironmentService
        self.serverAuthenticationController = serverAuthenticationController
        self.manifestLoader = manifestLoader
        self.fileSystem = fileSystem
        self.getProjectService = getProjectService
        self.gitController = gitController
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
    /// registry (`<state>/cas-proxy.sock.registry.sources`, honoring the same
    /// `TUIST_CAS_PROXY_REGISTRY` override the proxy reads).
    ///
    /// Upserts, so setting up a second project does not clobber the first.
    private func registerSource(
        fullHandle: String,
        trunk: String?,
        branch: String?,
        upload: Bool
    ) async throws {
        // Derived from the proxy's OWN socket, not from `stateDirectory`. The two
        // agree by default and diverge under `XDG_STATE_HOME`, which the socket
        // deliberately ignores (see `casProxySocketPath`) because the plugin must
        // resolve it from HOME alone. Writing this file where the proxy is not
        // reading loses the trunk silently: unscoped snapshots and untagged
        // publishes, with nothing to show for it.
        let sourcesPath: AbsolutePath
        if let registry = Environment.current.variables["TUIST_CAS_PROXY_REGISTRY"] {
            sourcesPath = try AbsolutePath(validating: registry + ".sources")
        } else {
            sourcesPath = try AbsolutePath(
                validating: Environment.current.casProxySocketPath().pathString + ".registry.sources"
            )
        }

        if try await !fileSystem.exists(sourcesPath.parentDirectory, isDirectory: true) {
            try await fileSystem.makeDirectory(at: sourcesPath.parentDirectory)
        }

        // The whole read-modify-write is serialized across processes. Atomic
        // rename gives a READER the old file or the new one, never a torn one,
        // but it does nothing for two setups racing: both read the registry
        // before either renames, and the later rename drops the project the
        // earlier one added, silently losing its trunk and upload policy. An
        // exclusive lock on a sidecar file makes the second setup wait for the
        // first, so it reads the already-updated registry and upserts onto it.
        let lockPath = sourcesPath.parentDirectory
            .appending(component: "\(sourcesPath.basename).lock")
        try await withRegistryLock(at: lockPath) {
            // Read every other project back: this rewrites the whole file, so
            // anything lost here is a project silently losing its policy. A
            // registry we cannot decode therefore fails the command rather than
            // being written over with just this project, which would erase every
            // other one's.
            var entries: [String: RegisteredSource] = [:]
            if try await fileSystem.exists(sourcesPath) {
                let contents = try await fileSystem.readTextFile(at: sourcesPath)
                entries = try JSONDecoder().decode([String: RegisteredSource].self, from: Data(contents.utf8))
            }
            entries[fullHandle] = RegisteredSource(trunk: trunk, branch: branch, upload: upload)

            let encoder = JSONEncoder()
            // Sorted so a rewrite that changes nothing produces the same bytes,
            // and unescaped because every key here is an `account/project`.
            encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
            let body = String(decoding: try encoder.encode(entries), as: UTF8.self)

            // Swapped in, never rewritten in place, and `rename` rather than a
            // remove followed by a write or a move: it is the only one of the
            // three that leaves no instant where the file is missing or
            // half-written.
            //
            // The proxy re-reads this on a timer while we write it, and it
            // carries the upload policy. A reader that finds no file sees no
            // projects, and an unknown project has to be allowed to upload, so
            // any gap here hands an opted-out project a window in which its Clang
            // outputs are published. `rename` gives every reader either the whole
            // old file or the whole new one, and both are answers we can live
            // with.
            let staged = sourcesPath.parentDirectory
                .appending(component: "\(sourcesPath.basename).\(UUID().uuidString)")
            try await fileSystem.writeText(body, at: staged)
            guard rename(staged.pathString, sourcesPath.pathString) == 0 else {
                let code = errno
                try? await fileSystem.remove(staged)
                throw SetupCacheCommandServiceError.registryNotReplaced(sourcesPath.pathString, code)
            }
        }
    }

    /// Runs `body` while holding an exclusive advisory lock on `lockPath`, so two
    /// `tuist setup cache` processes cannot interleave a read-modify-write of the
    /// registry. The lock file is created on demand and never removed: deleting
    /// it would reopen the race it closes. `flock` is released when the descriptor
    /// closes, including on a crash, so a killed setup cannot wedge the next one.
    private func withRegistryLock(at lockPath: AbsolutePath, _ body: () async throws -> Void) async throws {
        let descriptor = open(lockPath.pathString, O_CREAT | O_RDWR, 0o644)
        guard descriptor >= 0 else {
            throw SetupCacheCommandServiceError.registryNotLocked(lockPath.pathString, errno)
        }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else {
            throw SetupCacheCommandServiceError.registryNotLocked(lockPath.pathString, errno)
        }
        defer { flock(descriptor, LOCK_UN) }
        try await body()
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
