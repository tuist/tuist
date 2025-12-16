import ArgumentParser
import Foundation
import XcodeGraph

public struct ShareCommand: AsyncParsableCommand, TrackableParsableCommand {
    public var analyticsRequired: Bool { false }

    public init() {}

    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "share",
            abstract: "Generate a link to share your app."
        )
    }

    @Option(
        name: .shortAndLong,
        help: "The path to the directory that contains a Tuist or Xcode project with a buildable scheme that can output runnable artifacts.",
        completion: .directory
    )
    var path: String?

    @Argument(
        help: "The app name to be looked up in the built products directory or the paths to the app bundles or an .ipa archive.",
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

    @Flag(
        help: "The output in JSON format.",
        envKey: .shareJSON
    )
    var json: Bool = false

    @Option(
        help: "The track of the preview (e.g., 'beta', 'nightly').",
        envKey: .shareTrack
    )
    var track: String?

    public func run() async throws {
        try await ShareCommandService().run(
            path: path,
            apps: apps,
            configuration: configuration,
            platforms: platforms,
            derivedDataPath: derivedDataPath,
            json: json,
            track: track
        )
    }
}
