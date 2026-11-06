import ArgumentParser
import Foundation
import TuistEnvKey
import TuistNooraExtension

public struct AccountTokensListCommand: AsyncParsableCommand, NooraReadyCommand {
    public init() {}
    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "list",
            _superCommandName: "tokens",
            abstract: "List Tuist account tokens."
        )
    }

    @Argument(
        help: "The account handle to list the tokens for.",
        envKey: .accountTokensAccountHandle
    )
    var accountHandle: String

    @Option(
        name: .shortAndLong,
        help: "The path to the directory or a subdirectory of the project.",
        completion: .directory,
        envKey: .accountTokensPath
    )
    var path: String?

    @Flag(
        name: .long,
        help: "Output the result as JSON."
    )
    var json: Bool = false

    public var jsonThroughNoora: Bool = true

    public func run() async throws {
        try await AccountTokensListCommandService().run(
            accountHandle: accountHandle,
            path: path,
            json: json
        )
    }
}
