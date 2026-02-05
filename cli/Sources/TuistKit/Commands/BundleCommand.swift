import ArgumentParser
import Foundation

public struct BundleCommand: ParsableCommand {
    public init() {}

    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "bundle",
            abstract: "A set of commands to manage your project bundles.",
            subcommands: [
                BundleListCommand.self,
                BundleShowCommand.self,
            ]
        )
    }
}
