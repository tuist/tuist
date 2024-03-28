import ArgumentParser
import Foundation
import TSCBasic
import TuistSupport

public struct PluginTestCommand: ContextualizedAsyncParsableCommand {
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
        help: "Build both source and test targets."
    )
    var buildTests = false

    @Option(
        help: "Test the specified products."
    )
    var testProducts: [String] = []

    public func run() async throws {
        try await run(context: TuistContext())
    }

    public func run(context _: Context) async throws {
        try PluginTestService().run(
            path: pluginOptions.path,
            configuration: pluginOptions.configuration,
            buildTests: buildTests,
            testProducts: testProducts
        )
    }
}
