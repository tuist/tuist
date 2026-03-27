import ArgumentParser
import Foundation

public struct BuildXcodeTargetCommand: ParsableCommand {
    public init() {}
    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "target",
            abstract: "A set of commands to manage build targets.",
            subcommands: [BuildXcodeTargetListCommand.self]
        )
    }
}
