import ArgumentParser
import Foundation
import Path
import TuistSupport

struct MigrationSettingsToXCConfigCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "settings-to-xcconfig",
            _superCommandName: "migration",
            abstract: "It extracts the build settings from a project or a target into an xcconfig file."
        )
    }

    @Option(
        name: [.customShort("p"), .long],
        help: "The path to the Xcode project",
        completion: .directory,
        envKey: .migrationSettingsToXcconfigXcodeprojPath
    )
    var xcodeprojPath: String

    @Option(
        name: [.customShort("x"), .long],
        help: "The path to the .xcconfig file where build settings will be extracted.",
        completion: .directory,
        envKey: .migrationSettingsToXcconfigXcconfigPath
    )
    var xcconfigPath: String

    @Option(
        name: .shortAndLong,
        help: "The name of the target whose build settings will be extracted. When not passed, it extracts the build settings of the project.",
        completion: .default,
        envKey: .migrationSettingsToXcconfigTarget
    )
    var target: String?

    func run() throws {
        try MigrationSettingsToXCConfigService().run(
            xcodeprojPath: xcodeprojPath,
            xcconfigPath: xcconfigPath,
            target: target
        )
    }
}
