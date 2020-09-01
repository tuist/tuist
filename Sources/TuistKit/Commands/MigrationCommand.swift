import ArgumentParser
import Foundation
import TSCBasic

struct MigrationCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(commandName: "migration",
                             abstract: "A set of utilities to assist on the migration of Xcode projects to Tuist.", subcommands: [
                                 MigrationSettingsToXCConfigCommand.self,
                                 MigrationCheckEmptyBuildSettingsCommand.self,
                                 MigrationTargetsByDependenciesCommand.self
                             ])
    }
}
