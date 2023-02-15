import TSCBasic
import TuistSupport

final class PluginRunService {
    func run(
        path: String?,
        configuration: PluginCommand.PackageConfiguration,
        buildTests: Bool,
        skipBuild: Bool,
        task: String,
        arguments: [String]
    ) throws {
        var runCommand = [
            "swift", "run",
            "--configuration", configuration.rawValue,
        ]
        if let path = path {
            runCommand += [
                "--package-path",
                try AbsolutePath(validating: path, relativeTo: FileHandler.shared.currentPath).pathString,
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
        try System.shared.runAndPrint(runCommand)
    }
}
