import ArgumentParser
import Foundation
import TuistCore
import TuistServer
import TuistSupport

extension TargetQuery: @retroactive ExpressibleByArgument {
    public init?(argument: String) {
        self.init(stringLiteral: argument)
    }
}

public struct GenerateCommand: AsyncParsableCommand, RecentPathRememberableCommand {
    public init() {}

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

    @Argument(
        help: ArgumentHelp(
            """
            Targets to focus on, specified by name or tag query (e.g. 'tag:feature'). \
            Other targets will be linked as binaries if possible. \
            If no target is specified, all the project targets will be generated (except external ones, such as Swift packages).
            """,
            valueName: "query"
        )
    )
    var includedTargets: [TargetQuery] = []

    @Flag(
        name: .shortAndLong,
        help: "Don't open the project after generating it.",
        envKey: .generateOpen
    )
    var open: Bool = !Environment.current.isCI

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
            cacheStorageFactory: Extension.cacheStorageFactory,
            generatorFactory: Extension.generatorFactory
        ).run(
            path: path,
            includedTargets: Set(includedTargets),
            noOpen: !open,
            configuration: configuration,
            ignoreBinaryCache: !binaryCache
        )
    }
}
