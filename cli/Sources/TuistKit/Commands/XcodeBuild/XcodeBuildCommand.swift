import ArgumentParser
import Foundation

public struct XcodeBuildCommand: AsyncParsableCommand, TrackableParsableCommand {
    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "xcodebuild",
            abstract:
            "tuist xcodebuild extends the xcodebuild CLI with server capabilities such as insights and analytics.",
            subcommands: [
                XcodeBuildTestCommand.self,
                XcodeBuildTestWithoutBuildingCommand.self,
                XcodeBuildBuildCommand.self,
                XcodeBuildBuildForTestingCommand.self,
                XcodeBuildArchiveCommand.self,
                XcodeBuildCommandReorderer.self,
            ],
            defaultSubcommand: XcodeBuildCommandReorderer.self
        )
    }

    public var analyticsRequired: Bool { true }

    public init() {}
}
