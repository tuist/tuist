import ArgumentParser
import Foundation
import Path

struct MigrationCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "migration",
            abstract: "A set of utilities to assist in the migration of Xcode projects to Tuist.",
            subcommands: [
                MigrationSettingsToXCConfigCommand.self,
                MigrationCheckEmptyBuildSettingsCommand.self,
                MigrationTargetsByDependenciesCommand.self,
            ]
        )
    }
}
