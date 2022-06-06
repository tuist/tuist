import ArgumentParser
import FigSwiftArgumentParser
import Foundation
import TSCBasic

struct MigrationCommand: ParsableCommand {
    
    @OptionGroup var generateFigSpec: GenerateFigSpec<Self>
    
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
