import ArgumentParser
import Foundation
import Path

struct CloudCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        var subcommands: [ParsableCommand.Type] = []
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
        return CommandConfiguration(
            commandName: "cloud",
            abstract: "A set of commands to interact with the cloud.",
            subcommands: subcommands
        )
    }
}
