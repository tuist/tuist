import ArgumentParser
import Foundation

public struct TestXcodeCommand: ParsableCommand {
    public init() {}

    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "xcode",
            abstract: "A set of commands to inspect Xcode test details.",
            subcommands: [
                TestXcodeTargetCommand.self,
            ]
        )
    }
}

public struct TestXcodeTargetCommand: ParsableCommand {
    public init() {}

    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "target",
            abstract: "A set of commands to manage test targets.",
            subcommands: [TestXcodeTargetListCommand.self]
        )
    }
}
