import ArgumentParser
import Foundation
import Path

struct PluginCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "plugin",
            abstract: "A set of commands for plugin's management.",
            subcommands: [
                PluginArchiveCommand.self,
                PluginBuildCommand.self,
                PluginRunCommand.self,
                PluginTestCommand.self,
            ]
        )
    }

    enum PackageConfiguration: String, ExpressibleByArgument, RawRepresentable, EnumerableFlag {
        case debug, release
    }

    struct PluginOptions: ParsableArguments {
        @Option(
            name: .shortAndLong,
            help: "Choose configuration (default: debug).",
            envKey: .pluginOptionsConfiguration
        )
        var configuration: PackageConfiguration = .debug

        @Option(
            name: .shortAndLong,
            help: "The path to the directory that contains the definition of the plugin.",
            completion: .directory,
            envKey: .pluginOptionsPath
        )
        var path: String?
    }
}
