import ArgumentParser
import Foundation
import XcodeGraph

public struct ShareCommand: AsyncParsableCommand {
    public init() {}

    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "share",
            abstract: "Generate a link to share your app. Only simulator builds supported."
        )
    }

    @Option(
        name: .shortAndLong,
        help: "The path to the directory that contains a Tuist or Xcode project with a buildable scheme that can output runnable artifacts.",
        completion: .directory
    )
    var path: String?

    @Argument(
        help: "The app names to be looked up in the built products directory or the paths to the app bundles.",
        envKey: .shareApp
    )
    var apps: [String] = []

    @Option(
        name: [.long, .customShort("C")],
        help: "The configuration of the app to share. Ignored when the app paths are passed directly.",
        envKey: .shareConfiguration
    )
    var configuration: String?

    @Option(
        help: "The platforms (iOS, tvOS, visionOS, watchOS or macOS) to share the app for. Ignored when the app paths are passed directly.",
        completion: .list(["iOS", "tvOS", "macOS", "visionOS", "watchOS"]),
        envKey: .sharePlatform
    )
    var platforms: [XcodeGraph.Platform] = []

    @Option(
        help: "The derived data path to find the apps in. When absent, the system-configured one.",
        completion: .directory,
        envKey: .shareDerivedDataPath
    )
    var derivedDataPath: String?

    public func run() async throws {
        try await ShareService().run(
            path: path,
            apps: apps,
            configuration: configuration,
            platforms: platforms,
            derivedDataPath: derivedDataPath
        )
    }
}
