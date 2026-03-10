import ArgumentParser
import Foundation

public struct BuildFileCommand: ParsableCommand {
    public init() {}
    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "file",
            abstract: "A set of commands to manage build files.",
            subcommands: [BuildFileListCommand.self]
        )
    }
}
