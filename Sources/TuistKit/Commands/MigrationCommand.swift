import ArgumentParser
import Foundation
import TSCBasic

public struct MigrationCommand: ParsableCommand {
    // MARK: - Configuration
    
    public static var configuration: CommandConfiguration {
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
    
    // MARK: - Init
    
    public init() {}
}
