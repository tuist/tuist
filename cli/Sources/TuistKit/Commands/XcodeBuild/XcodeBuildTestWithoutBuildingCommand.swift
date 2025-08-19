import ArgumentParser
import Foundation
import TuistSupport
import XcodeGraph

public struct XcodeBuildTestWithoutBuildingCommand: AsyncParsableCommand, TrackableParsableCommand,
    RecentPathRememberableCommand
{
    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "test-without-building",
            _superCommandName: "xcodebuild",
            abstract: "tuist xcodebuild test-without-building extends the xcodebuild CLI test action with insights and selective testing capabilities."
        )
    }

    var analyticsRequired: Bool { true }

    public init() {}

    @Argument(
        parsing: .captureForPassthrough,
        help: "Arguments that will be passed through to the xcodebuild CLI. All arguments are forwarded to xcodebuild. Example: tuist xcodebuild test-without-building -scheme MyAppTests -destination 'platform=iOS Simulator,name=iPhone 15' -testConfiguration Debug"
    )
    public var passthroughXcodebuildArguments: [String] = []

    public func run() async throws {
        try await XcodeBuildTestCommandService(
            cacheStorageFactory: Extension.cacheStorageFactory,
            selectiveTestingGraphHasher: Extension.selectiveTestingGraphHasher,
            selectiveTestingService: Extension.selectiveTestingService
        )
        .run(
            passthroughXcodebuildArguments: ["test-without-building"] + passthroughXcodebuildArguments
        )
    }
}
