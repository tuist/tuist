import ArgumentParser
import Foundation
import TSCBasic

struct CloudCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "cloud",
            abstract: "A set of commands for cloud features.",
            subcommands: [
                CloudAuthCommand.self,
                CloudSessionCommand.self,
                CloudLogoutCommand.self,
            ]
        )
    }
}
