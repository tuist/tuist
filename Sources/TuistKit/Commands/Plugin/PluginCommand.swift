import ArgumentParser
import Foundation
import TSCBasic

struct PluginCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
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

    enum PackageConfiguration: String, ExpressibleByArgument, RawRepresentable {
        case debug, release
    }

    struct PluginOptions: ParsableArguments {
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
    }
}
