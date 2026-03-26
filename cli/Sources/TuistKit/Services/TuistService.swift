import Command
import FileSystem
import Foundation
import Path
import TuistConfigLoader
import TuistConstants
import TuistCore
import TuistEnvironment
import TuistLoader
import TuistLogging
import TuistPlugin
import TuistSupport

enum TuistServiceError: Error {
    case taskUnavailable
}

public final class TuistService: NSObject {
    private let pluginService: PluginServicing
    private let configLoader: ConfigLoading
    private let fileSystem: FileSysteming
    private let commandRunner: CommandRunning

    public init(
        pluginService: PluginServicing = PluginService(),
        configLoader: ConfigLoading = ConfigLoader(),
        fileSystem: FileSysteming = FileSystem(),
        commandRunner: CommandRunning = CommandRunner()
    ) {
        self.pluginService = pluginService
        self.configLoader = configLoader
        self.fileSystem = fileSystem
        self.commandRunner = commandRunner
    }

    public func run(
        arguments: [String],
        tuistBinaryPath: String
    ) async throws {
        var arguments = arguments

        let commandName = "tuist-\(arguments[0])"

        let currentPath = try await Environment.current.pathRelativeToWorkingDirectory(nil)
        let path: AbsolutePath
        if let pathOptionIndex = arguments.firstIndex(of: "--path") ?? arguments.firstIndex(of: "--p") {
            path = try AbsolutePath(
                validating: arguments[pathOptionIndex + 1],
                relativeTo: currentPath
            )
        } else {
            path = currentPath
        }

        let config = try await configLoader.loadConfig(path: path)

        var pluginPaths: [AbsolutePath] = if let configGeneratedProjectOptions = config.project.generatedProject {
            try await pluginService.remotePluginPaths(using: configGeneratedProjectOptions)
                .compactMap(\.releasePath)
        } else {
            []
        }

        if let pluginPath: String = Environment.current.variables["TUIST_CONFIG_PLUGIN_BINARY_PATH"] {
            let absolutePath = try AbsolutePath(validating: pluginPath)
            Logger.current.debug("Using plugin absolutePath \(absolutePath.description)", metadata: .subsection)
            pluginPaths.append(absolutePath)
        }

        var pluginExecutables: [AbsolutePath] = []
        for pluginPath in pluginPaths {
            let contents = try await fileSystem.contentsOfDirectory(pluginPath)
            pluginExecutables.append(contentsOf: contents.filter { $0.basename.hasPrefix("tuist-") })
        }

        if let pluginCommand = pluginExecutables.first(where: { $0.basename == commandName }) {
            arguments[0] = pluginCommand.pathString
        } else if await commandExists(commandName) {
            arguments[0] = commandName
        } else {
            throw TuistServiceError.taskUnavailable
        }

        try await commandRunner.run(arguments: arguments).pipedStream().awaitCompletion()
    }

    private func commandExists(_ name: String) async -> Bool {
        do {
            _ = try await commandRunner.run(arguments: ["/usr/bin/env", "which", name]).concatenatedString()
            return true
        } catch {
            return false
        }
    }
}
