import ArgumentParser
import Foundation
import TuistSupport
import XcodeGraph

public struct XcodeBuildBuildCommand: AsyncParsableCommand, TrackableParsableCommand, RecentPathRememberableCommand {
    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "build",
            _superCommandName: "xcodebuild",
            abstract: "tuist xcodebuild build extends the xcodebuild CLI build action with insights."
        )
    }

    var analyticsRequired: Bool { true }

    public init() {}

    @Argument(
        parsing: .captureForPassthrough,
        help: "xcodebuild arguments that will be passed through to the xcodebuild CLI."
    )
    public var passthroughXcodebuildArguments: [String] = []

    public func run() async throws {
        try await XcodeBuildBuildCommandService()
            .run(
                passthroughXcodebuildArguments: ["build"] + passthroughXcodebuildArguments
            )
    }
}
