import ArgumentParser
import Foundation
import TSCBasic

public struct PluginRunCommand: ParsableCommand {
    // MARK: - Configuration
    
    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "run",
            abstract: "Runs a plugin."
        )
    }
    
    // MARK: - Arguments and Flags

    @OptionGroup()
    var pluginOptions: PluginCommand.PluginOptions

    @Flag(
        help: "Build both source and test targets."
    )
    var buildTests = false

    @Flag(
        help: "Skip building the plugin."
    )
    var skipBuild = false

    @Argument(
        help: "The plugin task to run."
    )
    var task: String

    @Argument(
        help: "The arguments to pass to the plugin task."
    )
    var arguments: [String] = []

    // MARK: - Init
    
    public init() {}
    
    // MARK: - ParsableCommand
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
