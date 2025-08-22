import ArgumentParser
import Foundation
import TuistSupport
import XcodeGraph

public struct XcodeBuildArchiveCommand: AsyncParsableCommand, TrackableParsableCommand, RecentPathRememberableCommand {
    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "archive",
            _superCommandName: "xcodebuild",
            abstract: "tuist xcodebuild archive extends the xcodebuild CLI archive action with insights."
        )
    }

    var analyticsRequired: Bool { true }

    public init() {}

    @Argument(
        parsing: .captureForPassthrough,
        help: "Arguments that will be passed through to the xcodebuild CLI. All arguments are forwarded to xcodebuild. Example: tuist xcodebuild archive -scheme MyApp -archivePath ./build/MyApp.xcarchive"
    )
    public var passthroughXcodebuildArguments: [String] = []

    public func run() async throws {
        try await XcodeBuildBuildCommandService()
            .run(
                passthroughXcodebuildArguments: ["archive"] + passthroughXcodebuildArguments
            )
    }
}
