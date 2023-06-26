import ArgumentParser
import Foundation
import TSCBasic

public struct PluginBuildCommand: ParsableCommand {
    // MARK: - Configuration
    
    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "build",
            abstract: "Builds a plugin."
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
        help: "Print the binary output path."
    )
    var showBinPath = false

    @Option(
        help: "Build the specified targets."
    )
    var targets: [String] = []

    @Option(
        help: "Build the specified products."
    )
    var products: [String] = []
    
    // MARK: - Init
    
    public init() {}

    // MARK: - ParsableCommand
    
    public func run() throws {
        try PluginBuildService().run(
            path: pluginOptions.path,
            configuration: pluginOptions.configuration,
            buildTests: buildTests,
            showBinPath: showBinPath,
            targets: targets,
            products: products
        )
    }
}
