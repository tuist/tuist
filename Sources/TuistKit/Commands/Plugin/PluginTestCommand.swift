import ArgumentParser
import Foundation
import TSCBasic

public struct PluginTestCommand: ParsableCommand {
    // MARK: - Configuration

    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "test",
            abstract: "Tests a plugin."
        )
    }

    // MARK: - Arguments and Flags

    @OptionGroup()
    var pluginOptions: PluginCommand.PluginOptions

    @Flag(
        help: "Build both source and test targets."
    )
    var buildTests = false

    @Option(
        help: "Test the specified products."
    )
    var testProducts: [String] = []

    // MARK: - Init

    public init() {}

    // MARK: - ParsableCommand

    public func run() throws {
        try PluginTestService().run(
            path: pluginOptions.path,
            configuration: pluginOptions.configuration,
            buildTests: buildTests,
            testProducts: testProducts
        )
    }
}
