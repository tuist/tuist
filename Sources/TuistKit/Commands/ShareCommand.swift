import ArgumentParser
import Foundation
import XcodeGraph

public struct ShareCommand: AsyncParsableCommand {
    public init() {}

    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "share",
            abstract: "Generate a link to share your app. Currently supports sharing only simulator builds."
        )
    }

    @Option(
        name: .shortAndLong,
        help: "The path to the directory that contains the project with the target or scheme to be run.",
        completion: .directory
    )
    var path: String?

    @Argument(
        help: "The name of the app target to share or the paths to the built apps.",
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
        help: "The platforms (ios, tvos, visionos, watchos or macos) to share the app for. Ignored when the app paths are passed directly.",
        completion: .list(["ios", "tvos", "macos", "visionos", "watchos"]),
        envKey: .sharePlatform
    )
    var platforms: [XcodeGraph.Platform] = []

    @Option(
        help: "The derived data path to find the apps in.",
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
