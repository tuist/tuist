import ArgumentParser
import Foundation
import Path

public struct PluginRunCommand: ParsableCommand {
    public init() {}

    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "run",
            abstract: "Runs a plugin."
        )
    }

    @OptionGroup()
    var pluginOptions: PluginCommand.PluginOptions

    @Flag(
        help: "Build both source and test targets.",
        envKey: .pluginRunBuildTests
    )
    var buildTests: Bool = false

    @Flag(
        help: "Skip building the plugin.",
        envKey: .pluginRunSkipBuild
    )
    var skipBuild: Bool = false

    @Argument(
        help: "The plugin task to run.",
        envKey: .pluginRunTask
    )
    var task: String

    @Argument(
        help: "The arguments to pass to the plugin task.",
        envKey: .pluginRunArguments
    )
    var arguments: [String] = []

    public func run() throws {
        try PluginRunService().run(
            path: pluginOptions.path,
            configuration: pluginOptions.configuration,
            buildTests: buildTests,
            skipBuild: skipBuild,
            task: task,
            arguments: arguments
        )
    }
}
