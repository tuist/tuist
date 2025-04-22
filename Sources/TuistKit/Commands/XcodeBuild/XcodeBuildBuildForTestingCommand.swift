import ArgumentParser
import Foundation
import TuistSupport
import XcodeGraph

public struct XcodeBuildBuildForTestingCommand: AsyncParsableCommand, TrackableParsableCommand, RecentPathRememberableCommand {
    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "build-for-testing",
            _superCommandName: "xcodebuild",
            abstract: "tuist xcodebuild build-for-testing extends the xcodebuild CLI build-for-testing action with insights."
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
                passthroughXcodebuildArguments: ["build-for-testing"] + passthroughXcodebuildArguments
            )
    }
}
