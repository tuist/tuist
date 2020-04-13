import ArgumentParser
import Basic
import Foundation

struct CloudCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(commandName: "cloud",
                             abstract: "A set of commands for cloud-related operations", subcommands: [
                                 CloudAuthCommand.self,
                                 CloudSessionCommand.self,
                                 CloudLogoutCommand.self,
                             ])
    }
}
