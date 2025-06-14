import ArgumentParser
import Foundation

struct RegistryCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "registry",
            abstract: "A set of commands to interact with the Tuist Registry.",
            subcommands: [
                RegistrySetupCommand.self,
                RegistryLoginCommand.self,
                RegistryLogoutCommand.self,
            ]
        )
    }
}
