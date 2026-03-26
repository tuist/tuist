import Command
import Path
import TuistEnvironment
import TuistSupport

struct PluginRunService {
    private let commandRunner: CommandRunning

    init(commandRunner: CommandRunning = CommandRunner()) {
        self.commandRunner = commandRunner
    }

    func run(
        path: String?,
        configuration: PluginCommand.PackageConfiguration,
        buildTests: Bool,
        skipBuild: Bool,
        task: String,
        arguments: [String]
    ) async throws {
        var runCommand = [
            "swift", "run",
            "--configuration", configuration.rawValue,
        ]
        if let path {
            runCommand += [
                "--package-path",
                try await Environment.current.pathRelativeToWorkingDirectory(path).pathString,
            ]
        }
        if buildTests {
            runCommand.append(
                "--build-tests"
            )
        }
        if skipBuild {
            runCommand.append(
                "--skip-build"
            )
        }
        runCommand.append(task)
        runCommand += arguments
        try await commandRunner.run(arguments: runCommand).pipedStream().awaitCompletion()
    }
}
