import FileSystem
import Foundation
import Path
import TuistCore
import TuistLaunchctl
import TuistLoader
import TuistServer
import TuistSupport

enum SetupCacheCommandServiceError: Equatable, LocalizedError {
    case failedToLoadLaunchDaemon(String)
    case missingFullHandle
    case missingExecutablePath

    var errorDescription: String? {
        switch self {
        case let .failedToLoadLaunchDaemon(error):
            return "Failed to load LaunchDaemon: \(error)"
        case .missingFullHandle:
            return
                "The 'Tuist.swift' file is missing a fullHandle. See how to set up a Tuist project at: https://docs.tuist.dev/en/server/introduction/accounts-and-projects#projects"
        case .missingExecutablePath:
            return "Failed to determine the current tuist executable path"
        }
    }
}

struct SetupCacheCommandService {
    private let fileSystem: FileSysteming
    private let launchctlController: LaunchctlControlling
    private let configLoader: ConfigLoading
    private let serverEnvironmentService: ServerEnvironmentServicing
    private let manifestLoader: ManifestLoading

    init(
        fileSystem: FileSysteming = FileSystem(),
        launchctlController: LaunchctlControlling = LaunchctlController(),
        configLoader: ConfigLoading = ConfigLoader(),
        serverEnvironmentService: ServerEnvironmentServicing = ServerEnvironmentService(),
        manifestLoader: ManifestLoading = ManifestLoaderFactory().createManifestLoader()
    ) {
        self.fileSystem = fileSystem
        self.launchctlController = launchctlController
        self.configLoader = configLoader
        self.serverEnvironmentService = serverEnvironmentService
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

        let tuistBinaryPath = try await determineTuistBinaryPath()
        let launchDaemonPlistPath = try await createLaunchDaemonPlist(
            fullHandle: fullHandle,
            url: serverURL.absoluteString,
            tuistBinaryPath: tuistBinaryPath
        )

        try await launchDaemon(plistPath: launchDaemonPlistPath)

        Logger.current.debug("LaunchAgent configured and loaded successfully")

        if try await manifestLoader.hasRootManifest(at: path) {
            if let generationOptions = config.project.generatedProject?.generationOptions,
               generationOptions.enableCaching == true
            {
                Logger.current.info("Xcode Cache has been enabled 🎉", metadata: .success)
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
                    """
                )
            }
        } else {
            Logger.current.info(
                """
                Xcode Cache setup is almost complete!

                To finish the setup, set the following build settings in Xcode projects that you want to use caching for:
                COMPILATION_CACHE_ENABLE_CACHING=YES
                COMPILATION_CACHE_REMOTE_SERVICE_PATH=\(Environment.current.cacheSocketPathString(for: fullHandle))
                COMPILATION_CACHE_ENABLE_PLUGIN=YES
                COMPILATION_CACHE_ENABLE_DIAGNOSTIC_REMARKS=YES

                Note that `COMPILATION_CACHE_REMOTE_SERVICE_PATH` and `COMPILATION_CACHE_ENABLE_PLUGIN` are currently not directly exposed by Xcode and you need to manually add these as user-defined build settings.
                """
            )
        }
    }

    private func createLaunchDaemonPlist(
        fullHandle: String,
        url: String?,
        tuistBinaryPath: AbsolutePath
    ) async throws -> AbsolutePath {
        let launchAgentsDir = Environment.current.homeDirectory.appending(
            components: "Library", "LaunchAgents"
        )
        let plistFileName =
            "tuist.cache.\(fullHandle.replacingOccurrences(of: "/", with: "_")).plist"
        let plistPath = launchAgentsDir.appending(component: plistFileName)

        if try await !fileSystem.exists(launchAgentsDir) {
            try await fileSystem.makeDirectory(at: launchAgentsDir)
        }

        // If plist already exists, unload it first
        if try await fileSystem.exists(plistPath) {
            Logger.current.debug("Existing LaunchAgent found. Unloading...")
            do {
                try await launchctlController.unload(plistPath: plistPath)
            } catch {
                // It's ok if unload fails - the agent might not be loaded
                Logger.current.debug(
                    "Failed to unload existing LaunchAgent: \(error.localizedDescription)"
                )
            }
            try await fileSystem.remove(plistPath)
        }

        var programArguments = [
            tuistBinaryPath.pathString,
            "cache-start",
            fullHandle,
        ]

        if let url {
            programArguments.append(contentsOf: ["--url", url])
        }

        var environmentVariables: [String: String] = [:]
        if let token = Environment.current.tuistVariables[Constants.EnvironmentVariables.token] {
            environmentVariables["TUIST_TOKEN"] = token
        } else if let token = Environment.current.tuistVariables[Constants.EnvironmentVariables.deprecatedToken] {
            AlertController.current
                .warning("Use `TUIST_TOKEN` environment variable instead of `TUIST_CONFIG_TOKEN` to authenticate on the CI")
            environmentVariables["TUIST_TOKEN"] = token
        }

        let plistContent = launchAgentPlist(
            programPath: tuistBinaryPath.pathString,
            programArguments: programArguments,
            label: "tuist.cache.\(fullHandle.replacingOccurrences(of: "/", with: "_"))",
            environmentVariables: environmentVariables
        )

        try await fileSystem.writeText(plistContent, at: plistPath)

        Logger.current.debug("Created LaunchDaemon plist at: \(plistPath.pathString)")

        return plistPath
    }

    private func launchAgentPlist(
        programPath: String,
        programArguments: [String],
        label: String,
        environmentVariables: [String: String] = [:]
    ) -> String {
        let programArgumentsXML =
            programArguments
                .map { "<string>\($0)</string>" }
                .joined(separator: "\n\t\t")

        let environmentVariablesXML: String
        if environmentVariables.isEmpty {
            environmentVariablesXML = ""
        } else {
            let envVarEntries = environmentVariables.map { key, value in
                """
                \t<key>\(key)</key>
                \t<string>\(value)</string>
                """
            }.joined(separator: "\n\t")
            environmentVariablesXML = """
            <key>EnvironmentVariables</key>
            <dict>
            \(envVarEntries)
            </dict>
            """
        }

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(label)</string>
            <key>Program</key>
            <string>\(programPath)</string>
            <key>ProgramArguments</key>
            <array>
                \(programArgumentsXML)
            </array>
            \(environmentVariablesXML)
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <true/>
        </dict>
        </plist>
        """
    }

    private func launchDaemon(plistPath: AbsolutePath) async throws {
        do {
            try await launchctlController.load(plistPath: plistPath)
            Logger.current.debug("Loaded LaunchAgent")
        } catch {
            throw SetupCacheCommandServiceError.failedToLoadLaunchDaemon(error.localizedDescription)
        }
    }

    private func determineTuistBinaryPath() async throws -> AbsolutePath {
        guard let currentPath = Environment.current.currentExecutablePath() else {
            throw SetupCacheCommandServiceError.missingExecutablePath
        }

        // Check if the current executable is mise-managed
        if currentPath.pathString.contains("/.local/share/mise/installs/tuist/") {
            let homeDir = Environment.current.homeDirectory

            let misePath = homeDir.appending(
                components: ".local", "share", "mise", "installs", "tuist", "latest", "tuist"
            )
            if try await fileSystem.exists(misePath) {
                return misePath
            }

            // Check old mise path (with bin directory)
            let oldMisePath = homeDir.appending(
                components: ".local", "share", "mise", "installs", "tuist", "latest", "bin", "tuist"
            )
            if try await fileSystem.exists(oldMisePath) {
                return oldMisePath
            }
        }

        return currentPath
    }
}
