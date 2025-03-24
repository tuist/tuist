import ArgumentParser
import Foundation
import TuistCore
import TuistServer
import TuistSupport

public struct GenerateCommand: AsyncParsableCommand, RecentPathRememberableCommand {
    public init() {}

    public static var generatorFactory: GeneratorFactorying = GeneratorFactory()
    public static var cacheStorageFactory: CacheStorageFactorying = EmptyCacheStorageFactory()

    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "generate",
            abstract: "Generates an Xcode workspace to start working on the project.",
            subcommands: []
        )
    }

    @Option(
        name: .shortAndLong,
        help: "The path to the directory or a subdirectory of the project.",
        completion: .directory,
        envKey: .generatePath
    )
    var path: String?

    @Argument(help: """
    A list of targets to focus on. \
    Other targets will be linked as binaries if possible. \
    If no target is specified, all the project targets will be generated (except external ones, such as Swift packages).
    """)
    var sources: [String] = []

    @Flag(
        name: .shortAndLong,
        help: "Don't open the project after generating it.",
        envKey: .generateOpen
    )
    var open: Bool = !CIChecker().isCI()

    @Flag(
        help: "Ignore binary cache and use sources only.",
        envKey: .generateBinaryCache
    )
    var binaryCache: Bool = true

    @Option(
        name: .shortAndLong,
        help: "Configuration to generate for."
    )
    var configuration: String?

    public func run() async throws {
        try await GenerateService(
            cacheStorageFactory: Self.cacheStorageFactory,
            generatorFactory: Self.generatorFactory
        ).run(
            path: path,
            sources: Set(sources),
            noOpen: !open,
            configuration: configuration,
            ignoreBinaryCache: !binaryCache
        )
    }
}
