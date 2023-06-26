import ArgumentParser
import Foundation
import TSCBasic

public struct PluginCommand: ParsableCommand {
    // MARK: - Configuration

    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "plugin",
            abstract: "A set of commands for plugin's management.",
            subcommands: [
                PluginArchiveCommannd.self,
                PluginBuildCommand.self,
                PluginRunCommand.self,
                PluginTestCommand.self,
            ]
        )
    }

    public enum PackageConfiguration: String, ExpressibleByArgument, RawRepresentable {
        case debug, release
    }

    // MARK: - Arguments and flags

    public struct PluginOptions: ParsableArguments {
        @Option(
            name: .shortAndLong,
            help: "Choose configuration (default: debug)."
        )
        var configuration: PackageConfiguration = .debug

        @Option(
            name: .shortAndLong,
            help: "The path to the directory that contains the definition of the plugin.",
            completion: .directory
        )
        var path: String?

        public init() {}
    }

    // MARK: - Init

    public init() {}
}
