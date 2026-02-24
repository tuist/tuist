import ArgumentParser
import Foundation

public struct RegistryCommand: ParsableCommand {
    public init() {}

    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "registry",
            abstract: "A set of commands to interact with the Tuist Registry.",
            subcommands: subcommands
        )
    }

    private static var subcommands: [ParsableCommand.Type] {
        var commands: [ParsableCommand.Type] = [
            RegistrySetupCommand.self,
        ]
        #if os(macOS)
            commands.append(contentsOf: [
                RegistryLoginCommand.self,
                RegistryLogoutCommand.self,
            ])
        #endif
        return commands
    }
}
