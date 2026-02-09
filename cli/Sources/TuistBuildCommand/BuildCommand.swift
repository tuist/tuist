import ArgumentParser
import Foundation

public struct BuildCommand: AsyncParsableCommand {
    public init() {}

    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "build",
            abstract: "A set of commands to manage your project builds.",
            subcommands: subcommands,
            defaultSubcommand: defaultSubcommand
        )
    }

    private static var subcommands: [ParsableCommand.Type] {
        #if os(macOS)
            [BuildRunCommand.self, BuildListCommand.self, BuildShowCommand.self]
        #else
            [BuildListCommand.self, BuildShowCommand.self]
        #endif
    }

    private static var defaultSubcommand: ParsableCommand.Type? {
        #if os(macOS)
            BuildRunCommand.self
        #else
            nil
        #endif
    }
}
