import ArgumentParser
import Foundation
import TSCBasic

struct ScaleCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(commandName: "scale",
                             abstract: "A set of commands for scale features.", subcommands: [
                                 ScaleAuthCommand.self,
                                 ScaleSessionCommand.self,
                                 ScaleLogoutCommand.self,
                             ])
    }
}
