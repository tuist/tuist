import ArgumentParser
import Foundation
import TSCBasic

struct LabCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "lab",
            abstract: "A set of commands for lab features.",
            subcommands: [
                LabAuthCommand.self,
                LabSessionCommand.self,
                LabLogoutCommand.self,
            ]
        )
    }
}
