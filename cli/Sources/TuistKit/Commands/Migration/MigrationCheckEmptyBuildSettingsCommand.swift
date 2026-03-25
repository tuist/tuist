import Path
import TuistEnvironment

struct MigrationCheckEmptyBuildSettingsCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "check-empty-settings",
            _superCommandName: "migration",
            abstract: "It checks if the build settings of a project or target are empty. Otherwise it exits unsuccessfully."
        )
    }

    @Option(
        name: [.customShort("p"), .long],
        help: "The path to the Xcode project",
        completion: .directory,
        envKey: .migrationCheckEmptySettingsXcodeprojPath
    )
    var xcodeprojPath: String

    @Option(
        name: .shortAndLong,
        help: "The name of the target whose build settings will be checked. When not passed, it checks the build settings of the project.",
        envKey: .migrationCheckEmptySettingsTarget
    )
    var target: String?

    func run() async throws {
        let cwd = try await Environment.current.currentWorkingDirectory()
        try await MigrationCheckEmptyBuildSettingsService().run(
            xcodeprojPath: try AbsolutePath(validating: xcodeprojPath, relativeTo: cwd),
            target: target
        )
    }
}
