import ArgumentParser
import Foundation

public struct BuildXcodeCASOutputCommand: ParsableCommand {
    public init() {}
    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "cas-output",
            abstract: "A set of commands to manage build CAS outputs.",
            subcommands: [BuildXcodeCASOutputListCommand.self]
        )
    }
}
