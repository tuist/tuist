import ArgumentParser
import Foundation

public struct BuildCommand: AsyncParsableCommand {
    public init() {}

    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "build",
            abstract: "A set of commands to manage your project builds.",
            subcommands: [BuildListCommand.self, BuildShowCommand.self]
        )
    }
}
