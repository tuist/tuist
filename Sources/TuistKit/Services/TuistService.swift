import Foundation
import Path
import ServiceContextModule
import TuistCore
import TuistLoader
import TuistPlugin
import TuistSupport

enum TuistServiceError: Error {
    case taskUnavailable
}

final class TuistService: NSObject {
    private let pluginService: PluginServicing
    private let configLoader: ConfigLoading

    init(
        pluginService: PluginServicing = PluginService(),
        configLoader: ConfigLoading = ConfigLoader(
            manifestLoader: CachedManifestLoader()
        )
    ) {
        self.pluginService = pluginService
        self.configLoader = configLoader
    }

    func run(
        arguments: [String],
        tuistBinaryPath: String
    ) async throws {
        var arguments = arguments

        let commandName = "tuist-\(arguments[0])"

        let path: AbsolutePath
        if let pathOptionIndex = arguments.firstIndex(of: "--path") ?? arguments.firstIndex(of: "--p") {
            path = try AbsolutePath(
                validating: arguments[pathOptionIndex + 1],
                relativeTo: FileHandler.shared.currentPath
            )
        } else {
            path = FileHandler.shared.currentPath
        }

        let config = try await configLoader.loadConfig(path: path)

        var pluginPaths = try await pluginService.remotePluginPaths(using: config)
            .compactMap(\.releasePath)

        if let pluginPath: String = ProcessInfo.processInfo.environment["TUIST_CONFIG_PLUGIN_BINARY_PATH"] {
            let absolutePath = try AbsolutePath(validating: pluginPath)
            ServiceContext.current?.logger?.debug("Using plugin absolutePath \(absolutePath.description)", metadata: .subsection)
            pluginPaths.append(absolutePath)
        }

        let pluginExecutables = try pluginPaths
            .flatMap(FileHandler.shared.contentsOfDirectory)
            .filter { $0.basename.hasPrefix("tuist-") }

        if let pluginCommand = pluginExecutables.first(where: { $0.basename == commandName }) {
            arguments[0] = pluginCommand.pathString
        } else if System.shared.commandExists(commandName) {
            arguments[0] = commandName
        } else {
            throw TuistServiceError.taskUnavailable
        }

        try System.shared.runAndPrint(
            arguments,
            verbose: Environment.shared.isVerbose,
            environment: [
                Constants.EnvironmentVariables.tuistBinaryPath: tuistBinaryPath,
            ].merging(System.shared.env) { tuistEnv, _ in tuistEnv }
        )
    }
}
