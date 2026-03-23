import ArgumentParser
import Foundation
import TuistSupport

public struct XcodeBuildTestCommand: AsyncParsableCommand, TrackableParsableCommand, RecentPathRememberableCommand {
    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "test",
            _superCommandName: "xcodebuild",
            abstract: "tuist xcodebuild test extends the xcodebuild CLI test action with insights."
        )
    }

    public var analyticsRequired: Bool { true }

    public init() {}

    @Flag(
        name: .long,
        help: "When passed, the quarantine feature is disabled and tests run regardless of whether they are quarantined on the server."
    )
    public var skipQuarantine: Bool = false

    @Argument(
        parsing: .captureForPassthrough,
        help: "Arguments that will be passed through to the xcodebuild CLI. All arguments are forwarded to xcodebuild. Example: tuist xcodebuild test -scheme MyAppTests -destination 'platform=iOS Simulator,name=iPhone 15' -parallel-testing-enabled YES"
    )
    public var passthroughXcodebuildArguments: [String] = []

    public func run() async throws {
        try await XcodeBuildTestCommandService()
            .run(
                passthroughXcodebuildArguments: ["test"] + passthroughXcodebuildArguments,
                skipQuarantine: skipQuarantine
            )
    }
}
