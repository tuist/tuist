import ArgumentParser
import Foundation

public struct BundleArtifactCommand: ParsableCommand {
    public init() {}
    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "artifact",
            abstract: "A set of commands to manage bundle artifacts.",
            subcommands: [BundleArtifactListCommand.self]
        )
    }
}
