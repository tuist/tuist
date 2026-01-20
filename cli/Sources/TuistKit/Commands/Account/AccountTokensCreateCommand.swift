import ArgumentParser
import Foundation
import TuistServer
import TuistSupport

struct AccountTokensCreateCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "create",
            _superCommandName: "tokens",
            abstract: "Create a new Tuist account token."
        )
    }

    @Argument(
        help: "The account handle to create the token for.",
        envKey: .accountTokensAccountHandle
    )
    var accountHandle: String

    @Option(
        name: .shortAndLong,
        parsing: .upToNextOption,
        help: "The scopes for the token.",
        envKey: .accountTokensScopes
    )
    var scopes: [Components.Schemas.CreateAccountToken.scopesPayloadPayload]

    @Option(
        name: .shortAndLong,
        help:
        "A unique identifier for the token. Must be 1-32 characters and contain only alphanumeric characters, hyphens, and underscores.",
        envKey: .accountTokensName
    )
    var name: String

    @Option(
        name: .shortAndLong,
        help:
        "When the token should expire. Use format like '30d' (days), '6m' (months), or '1y' (years). If not specified, the token never expires.",
        envKey: .accountTokensExpires
    )
    var expires: String?

    @Option(
        name: .long,
        parsing: .upToNextOption,
        help:
        "The project handles to grant the token access to. If not provided, the token has access to all projects.",
        envKey: .accountTokensProjects
    )
    var projects: [String] = []

    @Option(
        name: .long,
        help: "The path to the directory or a subdirectory of the project.",
        completion: .directory,
        envKey: .accountTokensPath
    )
    var path: String?

    func run() async throws {
        try await AccountTokensCreateCommandService().run(
            accountHandle: accountHandle,
            scopes: scopes,
            name: name,
            expires: expires,
            projects: projects.isEmpty ? nil : projects,
            path: path
        )
    }
}

extension Components.Schemas.CreateAccountToken.scopesPayloadPayload: ExpressibleByArgument {
    public init?(argument: String) {
        self.init(rawValue: argument)
    }
}
