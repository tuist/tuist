import ArgumentParser
import Foundation
import TSCBasic

struct CloudCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        var subcommands: [ParsableCommand.Type] = []
        #if canImport(TuistCloud)
        subcommands = [
            CloudAuthCommand.self,
            CloudSessionCommand.self,
            CloudLogoutCommand.self,
            CloudInitCommand.self,
            CloudCleanCommand.self,
            CloudProjectCommand.self,
            CloudOrganizationCommand.self,
            CloudAnalyticsCommand.self,
        ]
        #endif
        return CommandConfiguration(
            commandName: "cloud",
            abstract: "A set of commands to interact with the cloud.",
            subcommands: subcommands
        )
    }
}
