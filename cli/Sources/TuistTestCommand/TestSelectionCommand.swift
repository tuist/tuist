import ArgumentParser
import Foundation

public struct TestSelectionCommand: AsyncParsableCommand {
    public init() {}

    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "selection",
            abstract: "Manage test selection data.",
            subcommands: [
                TestSelectionListCommand.self,
            ]
        )
    }
}
