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
        #if os(macOS)
            [
                RegistrySetupCommand.self,
                RegistryLoginCommand.self,
                RegistryLogoutCommand.self,
            ]
        #else
            []
        #endif
    }
}
