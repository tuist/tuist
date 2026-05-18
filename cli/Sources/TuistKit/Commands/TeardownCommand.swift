import ArgumentParser
import Foundation

public struct TeardownCommand: AsyncParsableCommand {
    public init() {}

    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "teardown",
            abstract: "Commands to tear down Tuist services previously set up with `tuist setup`",
            subcommands: [
                TeardownCacheCommand.self,
            ]
        )
    }
}
