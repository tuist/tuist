import ArgumentParser
import Foundation

public struct BuildXcodeCommand: ParsableCommand {
    public init() {}
    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "xcode",
            abstract: "A set of commands to inspect Xcode build details.",
            subcommands: [
                BuildXcodeTargetCommand.self,
                BuildXcodeFileCommand.self,
                BuildXcodeIssueCommand.self,
                BuildXcodeCacheTaskCommand.self,
                BuildXcodeCASOutputCommand.self,
            ]
        )
    }
}
