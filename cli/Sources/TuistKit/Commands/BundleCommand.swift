import ArgumentParser
import Foundation

struct BundleCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
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
