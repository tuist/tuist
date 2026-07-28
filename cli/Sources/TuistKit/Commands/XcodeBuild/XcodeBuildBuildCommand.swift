import ArgumentParser
import Foundation
import TuistEnvKey
import TuistSupport
import XcodeGraph

public struct XcodeBuildBuildCommand: AsyncParsableCommand, TrackableParsableCommand, RunReportingCommand {
    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "build",
            _superCommandName: "xcodebuild",
            abstract: "tuist xcodebuild build extends the xcodebuild CLI build action with insights."
        )
    }

    public var analyticsRequired: Bool { true }

    public init() {}

    @Argument(
        parsing: .captureForPassthrough,
        help: "Arguments that will be passed through to the xcodebuild CLI. All arguments are forwarded to xcodebuild. Example: tuist xcodebuild build -scheme MyApp -destination 'platform=iOS Simulator,name=iPhone 15'"
    )
    public var passthroughXcodebuildArguments: [String] = []

    @Option(
        name: .long,
        help: "Path where a JSON report of the run, including the dashboard URLs, will be saved.",
        completion: .file(),
        envKey: .runReportPath
    )
    public var runReportPath: String?

    public func run() async throws {
        try await XcodeBuildBuildCommandService()
            .run(
                passthroughXcodebuildArguments: ["build"] + passthroughXcodebuildArguments
            )
    }
}
