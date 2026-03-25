import ArgumentParser
import Foundation

public struct TestSelectiveTestingCommand: AsyncParsableCommand {
    public init() {}

    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "selective-testing",
            abstract: "Manage selective testing data.",
            subcommands: [
                TestSelectiveTestingListCommand.self,
            ]
        )
    }
}
