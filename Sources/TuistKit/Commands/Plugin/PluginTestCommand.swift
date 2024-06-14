import ArgumentParser
import Foundation
import Path

public struct PluginTestCommand: ParsableCommand {
    public init() {}

    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "test",

            abstract: "Tests a plugin."
        )
    }

    @OptionGroup()
    var pluginOptions: PluginCommand.PluginOptions

    @Flag(
        help: "Build both source and test targets.",
        envKey: .pluginTestBuildTests
    )
    var buildTests = false

    @Option(
        help: "Test the specified products.",
        envKey: .pluginTestTestProducts
    )
    var testProducts: [String] = []

    public func run() throws {
        try PluginTestService().run(
            path: pluginOptions.path,
            configuration: pluginOptions.configuration,
            buildTests: buildTests,
            testProducts: testProducts
        )
    }
}
