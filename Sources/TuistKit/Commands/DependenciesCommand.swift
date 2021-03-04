import ArgumentParser
import Foundation
import TSCBasic

struct DependenciesCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "dependencies",
            abstract: "[Experimental] A set of commands for project's dependencies managment.",
            subcommands: [
                DependenciesFetchCommand.self,
                DependenciesUpdateCommand.self,
            ]
        )
    }
}
